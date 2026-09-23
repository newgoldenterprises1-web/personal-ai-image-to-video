import "dotenv/config";
import express from "express";
import cors from "cors";
import multer from "multer";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { v4 as uuid } from "uuid";
import RunwayML from "@runwayml/sdk";
import { renderProject } from "./renderer.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(process.env.DATA_DIR || path.join(__dirname, "..", "data"));
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

const jobs = new Map();
const runway = process.env.RUNWAYML_API_SECRET ? new RunwayML({ apiKey: process.env.RUNWAYML_API_SECRET }) : null;

function publicFile(req, file) {
  return `${req.protocol}://${req.get("host")}/media/${path.relative(root, file).replaceAll(path.sep, "/")}`;
}

function requireRunway(res) {
  if (!runway) {
    res.status(503).json({ error: "Runway is not configured. Set RUNWAYML_API_SECRET on the server." });
    return false;
  }
  return true;
}

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, aiConfigured: Boolean(runway), ffmpeg: true, version: "1.0.0" });
});

app.post("/api/projects/:projectId/scenes", upload.single("image"), async (req, res) => {
  const { projectId } = req.params;
  if (!req.file) return res.status(400).json({ error: "image is required" });
  const dir = path.join(root, "projects", projectId, "images");
  await fs.mkdir(dir, { recursive: true });
  const ext = path.extname(req.file.originalname) || ".jpg";
  const target = path.join(dir, `${uuid()}${ext}`);
  await fs.rename(req.file.path, target);
  res.json({ path: target, url: publicFile(req, target), filename: path.basename(target) });
});

app.post("/api/generate", async (req, res) => {
  if (!requireRunway(res)) return;
  const { projectId, imagePath, prompt, ratio = "16:9", duration = 5, model = "gen4.5" } = req.body || {};
  if (!projectId || !imagePath || !prompt) return res.status(400).json({ error: "projectId, imagePath and prompt are required" });
  if (![4,5,6,8].includes(Number(duration)) && model === "gen4.5") {
    return res.status(400).json({ error: "gen4.5 generation duration must be 4, 5, 6 or 8 seconds" });
  }

  const jobId = uuid();
  jobs.set(jobId, { id: jobId, status: "UPLOADING", progress: 5, projectId });
  res.status(202).json({ jobId });

  (async () => {
    try {
      const image = await fs.readFile(imagePath);
      const ext = path.extname(imagePath).toLowerCase();
      const mime = ext === ".png" ? "image/png" : ext === ".webp" ? "image/webp" : "image/jpeg";
      jobs.set(jobId, { ...jobs.get(jobId), status: "UPLOADING", progress: 10 });
      const { uri } = await runway.uploads.createEphemeral(new File([image], path.basename(imagePath), { type: mime }));
      jobs.set(jobId, { ...jobs.get(jobId), status: "GENERATING", progress: 20 });

      const ratioMap = { "16:9": "1280:720", "9:16": "720:1280", "1:1": "960:960" };
      const task = await runway.imageToVideo.create({
        model,
        promptImage: uri,
        promptText: prompt,
        ratio: ratioMap[ratio] || "1280:720",
        duration: Number(duration)
      });
      jobs.set(jobId, { ...jobs.get(jobId), runwayTaskId: task.id, status: "GENERATING", progress: 30 });

      let result;
      for (;;) {
        await new Promise(r => setTimeout(r, 5000));
        result = await runway.tasks.retrieve(task.id);
        if (result.status === "SUCCEEDED") break;
        if (["FAILED", "CANCELED"].includes(result.status)) throw new Error(result.failure || "AI generation failed");
        jobs.set(jobId, { ...jobs.get(jobId), status: result.status, progress: Math.min(85, (jobs.get(jobId)?.progress || 30) + 5) });
      }

      const outputUrl = result.output?.[0];
      if (!outputUrl) throw new Error("AI task completed without a video output");
      const response = await fetch(outputUrl);
      if (!response.ok) throw new Error(`Could not download generated video: HTTP ${response.status}`);
      const buffer = Buffer.from(await response.arrayBuffer());
      const outDir = path.join(root, "projects", projectId, "clips");
      await fs.mkdir(outDir, { recursive: true });
      const out = path.join(outDir, `${jobId}.mp4`);
      await fs.writeFile(out, buffer);
      jobs.set(jobId, { ...jobs.get(jobId), status: "SUCCEEDED", progress: 100, videoPath: out });
    } catch (e) {
      jobs.set(jobId, { ...jobs.get(jobId), status: "FAILED", progress: 100, error: e?.message || String(e) });
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
  const { projectId, scenes, outputName = "final.mp4", ratio = "16:9", resolution = "1080p" } = req.body || {};
  if (!projectId || !Array.isArray(scenes) || scenes.length === 0) return res.status(400).json({ error: "projectId and scenes are required" });
  try {
    const output = await renderProject({ root, projectId, scenes, outputName, ratio, resolution });
    res.json({ ok: true, videoUrl: publicFile(req, output), path: output });
  } catch (e) {
    res.status(500).json({ error: e?.message || String(e) });
  }
});

app.get("/api/projects/:projectId/scene-files", async (req, res) => {
  const dir = path.join(root, "projects", req.params.projectId, "clips");
  try {
    const files = (await fs.readdir(dir)).filter(x => x.endsWith(".mp4"));
    res.json({ files: files.map(x => publicFile(req, path.join(dir, x))) });
  } catch {
    res.json({ files: [] });
  }
});

const port = Number(process.env.PORT || 8787);
app.listen(port, process.env.HOST || "0.0.0.0", () => {
  console.log(`Personal AI Image → Video server listening on http://0.0.0.0:${port}`);
});
