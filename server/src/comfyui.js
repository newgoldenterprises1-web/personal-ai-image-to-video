import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomInt } from "node:crypto";

const baseUrl = (process.env.COMFYUI_URL || "http://127.0.0.1:8188").replace(/\/$/, "");
const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const workflowPath = path.resolve(moduleDir, "..", process.env.COMFYUI_WORKFLOW_JSON || path.join("workflows", "image-to-video.json"));
const timeoutMs = Number(process.env.COMFYUI_TIMEOUT_MS || 20 * 60 * 1000);

const RATIO_SPECS = {
  "16:9": { width: 704, height: 416 },
  "9:16": { width: 416, height: 736 },
  "1:1": { width: 512, height: 512 }
};

export function deepReplace(value, replacements) {
  if (typeof value === "string") {
    if (Object.prototype.hasOwnProperty.call(replacements, value)) return replacements[value];
    let out = value;
    for (const [token, replacement] of Object.entries(replacements)) {
      out = out.split(token).join(String(replacement));
    }
    return out;
  }
  if (Array.isArray(value)) return value.map(item => deepReplace(item, replacements));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, deepReplace(item, replacements)]));
  }
  return value;
}

export function generationSpec(duration, ratio) {
  const numericDuration = Number(duration);
  if (!Number.isInteger(numericDuration) || numericDuration < 2 || numericDuration > 10) {
    throw new Error("Duration must be an integer from 2 to 10 seconds");
  }
  const spec = RATIO_SPECS[ratio];
  if (!spec) throw new Error("ratio must be 16:9, 9:16 or 1:1");
  return {
    ...spec,
    frames: numericDuration * 24 + 1,
    fps: 24,
    duration: numericDuration,
    ratio
  };
}

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    signal: options.signal || AbortSignal.timeout(60_000)
  });
  const text = await response.text();
  if (!response.ok) throw new Error("ComfyUI HTTP " + response.status + ": " + text.slice(0, 800));
  if (!text) return {};
  try { return JSON.parse(text); }
  catch { throw new Error("ComfyUI returned invalid JSON from " + url); }
}

export async function checkComfyUi() {
  try {
    const response = await fetch(baseUrl + "/system_stats", { signal: AbortSignal.timeout(3000) });
    return response.ok;
  } catch {
    return false;
  }
}

export async function loadComfyWorkflow() {
  const raw = await fs.readFile(workflowPath, "utf8");
  const workflow = JSON.parse(raw);
  if (!workflow || Array.isArray(workflow) || typeof workflow !== "object") {
    throw new Error("ComfyUI workflow must be an API-format node map");
  }
  return workflow;
}

export async function checkComfyWorkflow() {
  try {
    const workflow = await loadComfyWorkflow();
    const nodes = Object.values(workflow);
    const requiredTypes = [
      "CLIPLoader",
      "CheckpointLoaderSimple",
      "CLIPTextEncode",
      "LTXVImgToVideo",
      "LTXVConditioning",
      "LTXVScheduler",
      "SamplerCustom",
      "VAEDecode",
      "CreateVideo",
      "SaveVideo"
    ];
    if (!requiredTypes.every(type => nodes.some(node => node?.class_type === type))) {
      return false;
    }
    const serialized = JSON.stringify(workflow);
    return [
      "{{IMAGE}}",
      "{{PROMPT}}",
      "{{WIDTH}}",
      "{{HEIGHT}}",
      "{{FRAMES}}",
      "{{FPS}}",
      "{{SEED}}"
    ].every(token => serialized.includes(token));
  } catch {
    return false;
  }
}

function mimeForImage(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".png": return "image/png";
    case ".webp": return "image/webp";
    case ".jpg":
    case ".jpeg":
    default: return "image/jpeg";
  }
}

function extractVideoFile(historyItem) {
  const outputs = Object.values(historyItem?.outputs || {});
  const videoExtensions = new Set([".mp4", ".mov", ".mkv", ".webm"]);
  for (const nodeOutput of outputs) {
    for (const key of ["videos", "gifs", "images"]) {
      for (const file of nodeOutput?.[key] || []) {
        const filename = String(file?.filename || "");
        if (videoExtensions.has(path.extname(filename).toLowerCase())) return file;
      }
    }
  }
  return null;
}

export async function generateWithComfyUI({ imagePath, prompt, duration, ratio, onProgress }) {
  const workflowRaw = await fs.readFile(workflowPath, "utf8");
  const workflow = JSON.parse(workflowRaw);
  const spec = generationSpec(duration, ratio);
  const imageBuffer = await fs.readFile(imagePath);

  const form = new FormData();
  form.append("image", new Blob([imageBuffer], { type: mimeForImage(imagePath) }), path.basename(imagePath));
  form.append("overwrite", "true");

  const upload = await jsonRequest(baseUrl + "/upload/image", { method: "POST", body: form });
  if (!upload?.name) throw new Error("ComfyUI image upload did not return a filename");

  const replacements = {
    "{{IMAGE}}": upload.name,
    "{{PROMPT}}": String(prompt).slice(0, 8000),
    "{{DURATION}}": spec.duration,
    "{{RATIO}}": spec.ratio,
    "{{WIDTH}}": spec.width,
    "{{HEIGHT}}": spec.height,
    "{{FRAMES}}": spec.frames,
    "{{FPS}}": spec.fps,
    "{{SEED}}": randomInt(0, 0xFFFFFFFF)
  };

  const promptWorkflow = deepReplace(workflow, replacements);
  const queued = await jsonRequest(baseUrl + "/prompt", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ prompt: promptWorkflow })
  });

  const promptId = queued?.prompt_id;
  if (!promptId) {
    const details = queued?.node_errors ? JSON.stringify(queued.node_errors) : JSON.stringify(queued);
    throw new Error("ComfyUI did not return a prompt_id: " + details.slice(0, 1200));
  }

  onProgress?.(25);
  const startedAt = Date.now();

  for (;;) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error("ComfyUI generation timed out. Check the local GPU/VRAM and workflow logs.");
    }
    await new Promise(resolve => setTimeout(resolve, 2000));
    const history = await jsonRequest(baseUrl + "/history/" + encodeURIComponent(promptId));
    const item = history?.[promptId];

    if (!item) {
      onProgress?.(Math.min(85, 25 + Math.floor((Date.now() - startedAt) / 5000)));
      continue;
    }

    const messages = item?.status?.messages || [];
    const executionError = messages.some(message => Array.isArray(message) && message[0] === "execution_error");
    if (item?.status?.status_str === "error" || executionError) {
      const errorText = messages.map(message => Array.isArray(message) ? JSON.stringify(message[1] || message) : String(message)).join(" ");
      throw new Error("ComfyUI workflow execution failed" + (errorText ? ": " + errorText.slice(0, 1200) : ""));
    }

    const file = extractVideoFile(item);
    if (file?.filename) {
      const query = new URLSearchParams({
        filename: file.filename,
        subfolder: file.subfolder || "",
        type: file.type || "output"
      });
      const response = await fetch(baseUrl + "/view?" + query.toString(), {
        signal: AbortSignal.timeout(120_000)
      });
      if (!response.ok) throw new Error("Could not download ComfyUI output: HTTP " + response.status);
      const contentType = response.headers.get("content-type") || "";
      if (!contentType.startsWith("video/") && !/\.(mp4|mov|mkv|webm)$/i.test(file.filename)) {
        throw new Error("ComfyUI returned a non-video output (" + file.filename + ")");
      }
      onProgress?.(95);
      return Buffer.from(await response.arrayBuffer());
    }

    if (item?.status?.completed) {
      throw new Error("ComfyUI completed without a video output. Check the workflow SaveVideo node.");
    }
  }
}

export { baseUrl, workflowPath };