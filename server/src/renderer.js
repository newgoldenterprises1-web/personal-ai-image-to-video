import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    p.stderr.on("data", data => { stderr += data.toString(); });
    p.on("error", reject);
    p.on("close", code => code === 0
      ? resolve()
      : reject(new Error(stderr.trim() || `${cmd} exited ${code}`)));
  });
}

export async function checkFfmpeg() {
  try {
    await run("ffmpeg", ["-version"]);
    return true;
  } catch {
    return false;
  }
}

export function safeOutputName(name) {
  const cleaned = String(name || "final.mp4").replace(/[^a-zA-Z0-9._-]/g, "_");
  return cleaned.toLowerCase().endsWith(".mp4") ? cleaned : `${cleaned}.mp4`;
}

export function sceneToAbsolute(root, scene, projectId) {
  if (!scene || typeof scene !== "object") throw new Error("Invalid scene");
  const rootResolved = path.resolve(root);
  const projectRoot = projectId
    ? path.join(rootResolved, "projects", String(projectId))
    : rootResolved;

  if (scene.videoPath) {
    const absolute = path.resolve(rootResolved, String(scene.videoPath));
    if (absolute.startsWith(projectRoot + path.sep)) return absolute;
  }

  if (scene.videoUrl) {
    const marker = "/media/";
    const index = String(scene.videoUrl).indexOf(marker);
    if (index < 0) throw new Error("Invalid scene video URL");
    const relative = String(scene.videoUrl).slice(index + marker.length).replaceAll("/", path.sep);
    const absolute = path.resolve(rootResolved, relative);
    if (absolute.startsWith(projectRoot + path.sep)) return absolute;
  }

  throw new Error("Scene must contain videoPath or videoUrl");
}

export async function renderProject({ root, projectId, scenes, outputName, ratio, resolution }) {
  const rootResolved = path.resolve(root);
  const dir = path.join(rootResolved, "projects", projectId, "render");
  const normalizedDir = path.join(dir, "normalized");
  await fs.mkdir(normalizedDir, { recursive: true });

  const valid = scenes.filter(Boolean);
  if (!valid.length) throw new Error("No generated scene clips are ready");

  const size = ratio === "9:16"
    ? "1080:1920"
    : ratio === "1:1"
      ? "1080:1080"
      : "1920:1080";
  const crf = resolution === "720p" ? "21" : "18";
  const vf = [
    `scale=${size}:force_original_aspect_ratio=decrease`,
    `pad=${size}:(ow-iw)/2:(oh-ih)/2:color=black`,
    "format=yuv420p"
  ].join(",");
  const normalizedFiles = [];

  for (let index = 0; index < valid.length; index += 1) {
    const scene = valid[index];
    const absolute = sceneToAbsolute(rootResolved, scene, projectId);
    await fs.access(absolute);

    const normalized = path.join(normalizedDir, `scene-${String(index + 1).padStart(4, "0")}.mp4`);
    await run("ffmpeg", [
      "-y",
      "-i", absolute,
      "-vf", vf,
      "-r", "24",
      "-fps_mode", "cfr",
      "-an",
      "-c:v", "libx264",
      "-preset", "medium",
      "-crf", crf,
      "-pix_fmt", "yuv420p",
      "-movflags", "+faststart",
      normalized
    ]);
    normalizedFiles.push(normalized);
  }

  const listFile = path.join(dir, "concat.txt");
  const lines = normalizedFiles.map(file => `file '${file.replaceAll("'", "'\\''")}'`);
  await fs.writeFile(listFile, lines.join("\n") + "\n", "utf8");

  const target = path.join(dir, safeOutputName(outputName));
  await run("ffmpeg", [
    "-y",
    "-f", "concat",
    "-safe", "0",
    "-i", listFile,
    "-c", "copy",
    "-movflags", "+faststart",
    target
  ]);

  return target;
}
