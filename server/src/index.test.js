import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import http from "node:http";

test("backend starts and exposes the free-local health contract", async () => {
  const dataDir = await fs.mkdtemp(path.join(os.tmpdir(), "personal-ai-video-server-"));
  const port = 18787 + (process.pid % 500);
  const env = {
    ...process.env,
    PORT: String(port),
    HOST: "127.0.0.1",
    DATA_DIR: dataDir,
    COMFYUI_URL: "http://127.0.0.1:1",
    COMFYUI_WORKFLOW_JSON: path.resolve("workflows/image-to-video.json"),
  };
  const child = spawn(process.execPath, ["src/index.js"], {
    cwd: process.cwd(),
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    const requestJson = (pathname, options = {}) => new Promise((resolve, reject) => {
      const request = http.request(
        {hostname:"127.0.0.1", port, path:pathname, method:options.method || "GET", headers:options.headers || {}},
        response => {
          let data = "";
          response.setEncoding("utf8");
          response.on("data", chunk => { data += chunk; });
          response.on("end", () => resolve({status:response.statusCode, body:data}));
        }
      );
      request.on("error", reject);
      if (options.body) request.write(options.body);
      request.end();
    });

    let response;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 100));
      try {
        response = await requestJson("/api/health");
        break;
      } catch {}
    }
    assert.ok(response, "backend did not become reachable");
    assert.equal(response.status, 200);
    const health = JSON.parse(response.body);
    assert.equal(health.provider, "comfyui-local");
    assert.equal(health.paidApiRequired, false);
    assert.equal(health.persistentJobs, true);
    assert.equal(health.aiConfigured, false);

    const generation = await requestJson("/api/generate", {
      method:"POST",
      headers:{"content-type":"application/json"},
      body:JSON.stringify({projectId:"p1",imagePath:"/tmp/missing.jpg",prompt:"test"})
    });
    assert.equal(generation.status, 503);
    const generationBody = JSON.parse(generation.body);
    assert.match(generationBody.error, /ComfyUI/);
  } finally {
    child.kill("SIGTERM");
    await new Promise(resolve => {
      child.once("exit", resolve);
      setTimeout(resolve, 2000);
    });
    await fs.rm(dataDir, {recursive:true,force:true});
  }
});