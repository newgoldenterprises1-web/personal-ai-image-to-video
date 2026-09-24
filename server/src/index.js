import "dotenv/config";
import express from "express";
import cors from "cors";
import multer from "multer";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { v4 as uuid } from "uuid";
import { generateWithComfyUI, checkComfyUi } from "./comfyui.js";
import { renderProject, checkFfmpeg } from "./renderer.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(process.env.DATA_DIR || path.join(__dirname, "..", "data"));
const rootResolved = path.resolve(root);
await fs.mkdir(root, { recursive: true });

const app = express();
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "2mb" }));
app.use("/media", express.static(root));

const upload = multer({
  dest: path.join(root, "uploads"),
  limits: { fileSize: 200 * 1024 * 1024, files: 50 }
});

await fs.mkdir(path.join(root, "uploads"), { recursive: true });
await fs.mkdir(path.join(root, "projects"), { recursive: true });

const jobsFile = path.join(root, "jobs.json");
const jobs = new Map();
let persistTimer = null;

async function persistJobsNow() {
  const temp = jobsFile + ".tmp";
  await fs.writeFile(temp, JSON.stringify([...jobs.values()], null, 2), "utf8");
  await fs.rename(temp, jobsFile);
}

function persistJobs() {
  if (persistTimer) return;
  persistTimer = setTimeout(() => {
    persistTimer = null;
    persistJobsNow().catch(error => console.error("Could not persist jobs:", error));
  }, 100);
}

function updateJob(jobId, patch) {
  const current = jobs.get(jobId) || { id: jobId };
  jobs.set(jobId, { ...current, ...patch });
  persistJobs();
  return jobs.get(jobId);
}

try {
  const saved = JSON.parse(await fs.readFile(jobsFile, "utf8"));
  if (Array.isArray(saved)) {
    for (const job of saved) {
      if (!job?.id) continue;
      if (["SUCCEEDED", "FAILED", "CANCELED"].includes(job.status)) {
        jobs.set(job.id, job);
      } else {
        jobs.set(job.id, {
          ...job,
          status: "FAILED",
          progress: 100,
          error: "Generation was interrupted because the backend restarted."
        });
      }
    }
  }
  await persistJobsNow();
} catch (error) {
  if (error?.code !== "ENOENT") {
    console.error("Could not load persisted jobs:", error);
  }
}

function publicFile(req, file) {
  const relative = path.relative(rootResolved, path.resolve(file)).replaceAll(path.sep, "/");
  return req.protocol + "://" + req.get("host") + "/media/" + relative;
}

function safeProjectId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,100}$/.test(value);
}

async function requireComfyUI(res) {
  const available = await checkComfyUi();
  if (!available) {
    res.status(503).json({
      error: "Free local AI backend is not running. Start ComfyUI on this PC and configure COMFYUI_URL/COMFYUI_WORKFLOW_JSON."
    });
    return false;
  }
  return true;
}

app.get("/api/health", async (_req, res) => {
  res.json({
    ok: true,
    aiConfigured: await checkComfyUi(),
    ffmpeg: await checkFfmpeg(),
    version: "2.1.0",
    persistentJobs: true,
    provider: "comfyui-local",
    paidApiRequired: false
  });
});

app.post("/api/projects/:projectId/scenes", upload.single("image"), async (req, res) => {
  try {
    const { projectId } = req.params;
    if (!safeProjectId(projectId)) return res.status(400).json({ error: "invalid projectId" });
    if (!req.file) return res.status(400).json({ error: "image is required" });

    const dir = path.join(rootResolved, "projects", projectId, "images");
    await fs.mkdir(dir, { recursive: true });
    const ext = path.extname(req.file.originalname).toLowerCase();
    const allowed = new Set([".jpg", ".jpeg", ".png", ".webp"]);
    const finalExt = allowed.has(ext) ? ext : ".jpg";
    const target = path.join(dir, uuid() + finalExt);
    await fs.rename(req.file.path, target);

    res.json({
      path: target,
      url: publicFile(req, target),
      filename: path.basename(target)
    });
  } catch (error) {
    if (req.file?.path) await fs.rm(req.file.path, { force: true }).catch(() => {});
    res.status(500).json({ error: error?.message || String(error) });
  }
});

app.post("/api/generate", async (req, res) => {
  if (!(await requireComfyUI(res))) return;

  const {
    projectId,
    imagePath,
    prompt,
    ratio = "16:9",
    duration = 5
  } = req.body || {};

  if (!safeProjectId(projectId) || !imagePath || !prompt) {
    return res.status(400).json({ error: "projectId, imagePath and prompt are required" });
  }

  const numericDuration = Number(duration);
  if (!Number.isInteger(numericDuration) || numericDuration < 2 || numericDuration > 10) {
    return res.status(400).json({ error: "Duration must be an integer from 2 to 10 seconds" });
  }
  if (!["16:9", "9:16", "1:1"].includes(ratio)) {
    return res.status(400).json({ error: "ratio must be 16:9, 9:16 or 1:1" });
  }

  const safeImagePath = path.resolve(String(imagePath));
  if (!safeImagePath.startsWith(rootResolved + path.sep)) {
    return res.status(400).json({ error: "imagePath must belong to this server project storage" });
  }

  const jobId = uuid();
  updateJob(jobId, {
    id: jobId,
    status: "UPLOADING",
    progress: 5,
    projectId,
    provider: "comfyui-local",
    duration: numericDuration,
    ratio
  });

  res.status(202).json({ jobId });

  (async () => {
    try {
      updateJob(jobId, { status: "GENERATING", progress: 10 });

      const buffer = await generateWithComfyUI({
        imagePath: safeImagePath,
        prompt,
        duration: numericDuration,
        ratio,
        onProgress: progress => updateJob(jobId, {
          status: "GENERATING",
          progress
        })
      });

      const outDir = path.join(rootResolved, "projects", projectId, "clips");
      await fs.mkdir(outDir, { recursive: true });
      const out = path.join(outDir, jobId + ".mp4");
      await fs.writeFile(out, buffer);

      updateJob(jobId, {
        status: "SUCCEEDED",
        progress: 100,
        videoPath: out
      });
    } catch (error) {
      updateJob(jobId, {
        status: "FAILED",
        progress: 100,
        error: error?.message || String(error)
      });
    }
  })();
});

app.get("/api/jobs/:jobId", (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: "job not found" });

  const payload = { ...job };
  if (payload.videoPath) payload.videoUrl = publicFile(req, payload.videoPath);
  res.json(payload);
});

app.post("/api/render", async (req, res) => {
  const {
    projectId,
    scenes,
    outputName = "final.mp4",
    ratio = "16:9",
    resolution = "1080p"
  } = req.body || {};

  if (!safeProjectId(projectId) || !Array.isArray(scenes) || scenes.length === 0) {
    return res.status(400).json({ error: "projectId and scenes are required" });
  }
  if (!["16:9", "9:16", "1:1"].includes(ratio)) {
    return res.status(400).json({ error: "ratio must be 16:9, 9:16 or 1:1" });
  }
  if (!["720p", "1080p"].includes(resolution)) {
    return res.status(400).json({ error: "resolution must be 720p or 1080p" });
  }
  if (!(await checkFfmpeg())) {
    return res.status(503).json({ error: "FFmpeg is not installed or not available on PATH" });
  }

  try {
    const output = await renderProject({
      root: rootResolved,
      projectId,
      scenes,
      outputName,
      ratio,
      resolution
    });
    res.json({
      ok: true,
      videoUrl: publicFile(req, output),
      path: output
    });
  } catch (error) {
    res.status(500).json({ error: error?.message || String(error) });
  }
});

app.get("/api/projects/:projectId/scene-files", async (req, res) => {
  if (!safeProjectId(req.params.projectId)) {
    return res.status(400).json({ error: "invalid projectId" });
  }

  const dir = path.join(rootResolved, "projects", req.params.projectId, "clips");
  try {
    const files = (await fs.readdir(dir)).filter(name => name.toLowerCase().endsWith(".mp4"));
    res.json({
      files: files.map(name => publicFile(req, path.join(dir, name)))
    });
  } catch {
    res.json({ files: [] });
  }
});

const port = Number(process.env.PORT || 8787);
app.listen(port, process.env.HOST || "0.0.0.0", () => {
  console.log("Personal AI Image → Video server listening on http://0.0.0.0:" + port);
});