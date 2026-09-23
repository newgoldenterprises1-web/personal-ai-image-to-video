import fs from "node:fs/promises";
import path from "node:path";

const baseUrl = (process.env.COMFYUI_URL || "http://127.0.0.1:8188").replace(/\/$/, "");
const workflowPath = path.resolve(process.env.COMFYUI_WORKFLOW_JSON || "./workflows/image-to-video.json");

function deepReplace(value, replacements) {
  if (typeof value === "string") {
    let out = value;
    for (const [token, replacement] of Object.entries(replacements)) {
      out = out.split(token).join(replacement);
    }
    return out;
  }
  if (Array.isArray(value)) return value.map(item => deepReplace(item, replacements));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, deepReplace(item, replacements)]));
  }
  return value;
}

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  if (!response.ok) throw new Error(`ComfyUI HTTP ${response.status}: ${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : {};
}

export async function checkComfyUi() {
  try {
    const response = await fetch(`${baseUrl}/system_stats`);
    return response.ok;
  } catch {
    return false;
  }
}

export async function generateWithComfyUI({ imagePath, prompt, duration, ratio, onProgress }) {
  const workflowRaw = await fs.readFile(workflowPath, "utf8");
  const workflow = JSON.parse(workflowRaw);

  const imageBuffer = await fs.readFile(imagePath);
  const form = new FormData();
  form.append("image", new Blob([imageBuffer]), path.basename(imagePath));
  form.append("overwrite", "true");
  const upload = await jsonRequest(`${baseUrl}/upload/image`, { method: "POST", body: form });

  const replacements = {
    "{{IMAGE}}": upload.name,
    "{{PROMPT}}": String(prompt).slice(0, 4000),
    "{{DURATION}}": String(duration),
    "{{RATIO}}": String(ratio)
  };
  const promptWorkflow = deepReplace(workflow, replacements);
  const queued = await jsonRequest(`${baseUrl}/prompt`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ prompt: promptWorkflow })
  });

  const promptId = queued.prompt_id;
  if (!promptId) throw new Error("ComfyUI did not return a prompt_id");
  onProgress?.(25);

  for (;;) {
    await new Promise(resolve => setTimeout(resolve, 2000));
    const history = await jsonRequest(`${baseUrl}/history/${encodeURIComponent(promptId)}`);
    const item = history[promptId];
    if (!item) {
      onProgress?.(Math.min(85, 25 + Math.floor(Math.random() * 5)));
      continue;
    }

    if (item.status?.status_str === "error" || item.status?.completed === false && item.status?.messages?.some(m => m?.[0] === "execution_error")) {
      throw new Error("ComfyUI workflow execution failed");
    }

    const outputs = Object.values(item.outputs || {});
    for (const nodeOutput of outputs) {
      for (const key of ["gifs", "videos", "images"]) {
        for (const file of nodeOutput?.[key] || []) {
          if (file?.filename) {
            const query = new URLSearchParams({
              filename: file.filename,
              subfolder: file.subfolder || "",
              type: file.type || "output"
            });
            const response = await fetch(`${baseUrl}/view?${query}`);
            if (!response.ok) throw new Error(`Could not download ComfyUI output: HTTP ${response.status}`);
            onProgress?.(95);
            return Buffer.from(await response.arrayBuffer());
          }
        }
      }
    }

    if (item.status?.completed) throw new Error("ComfyUI completed without a video output");
  }
}

export { baseUrl, workflowPath };
