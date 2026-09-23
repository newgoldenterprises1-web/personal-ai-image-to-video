import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    p.stderr.on("data", d => { stderr += d.toString(); });
    p.on("error", reject);
    p.on("close", code => code === 0 ? resolve() : reject(new Error(stderr || `${cmd} exited ${code}`)));
  });
}

export async function renderProject({ root, projectId, scenes, outputName, ratio, resolution }) {
  const dir = path.join(root, "projects", projectId, "render");
  await fs.mkdir(dir, { recursive: true });
  const listFile = path.join(dir, "concat.txt");
  const valid = scenes.filter(s => s && s.videoUrl).map(s => s.videoUrl);
  if (!valid.length) throw new Error("No generated scene clips are ready to render");

  const lines = [];
  for (const file of valid) {
    const marker = "/media/";
    const idx = file.indexOf(marker);
    if (idx < 0) throw new Error("Invalid scene video URL");
    const relative = file.slice(idx + marker.length).replaceAll("/", path.sep);
    const absolute = path.join(root, relative);
    await fs.access(absolute);
    lines.push(`file '${absolute.replaceAll("'", "'\\''")}'`);
  }
  await fs.writeFile(listFile, lines.join("\n") + "\n", "utf8");

  const size = ratio === "9:16" ? "1080:1920" : ratio === "1:1" ? "1080:1080" : "1920:1080";
  const target = path.join(dir, outputName.replace(/[^a-zA-Z0-9._-]/g, "_"));
  const vf = `scale=${size}:force_original_aspect_ratio=decrease,pad=${size}:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p`;
  const crf = resolution === "720p" ? "21" : "18";

  await run("ffmpeg", [
    "-y", "-f", "concat", "-safe", "0", "-i", listFile,
    "-vf", vf, "-c:v", "libx264", "-preset", "medium", "-crf", crf,
    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", target
  ]);
  return target;
}
