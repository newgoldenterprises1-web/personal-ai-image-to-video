import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "personal-ai-video-comfy-"));
const workflowPath = path.join(tempDir, "workflow.json");
const imagePath = path.join(tempDir, "input.jpg");
await fs.writeFile(workflowPath, JSON.stringify({
  "1": {"class_type":"LoadImage","inputs":{"image":"{{IMAGE}}","upload":"image"}},
  "2": {"class_type":"CLIPTextEncode","inputs":{"text":"{{PROMPT}}"}},
  "3": {"class_type":"CreateVideo","inputs":{"images":["1",0],"fps":"{{FPS}}"}}
}), "utf8");
await fs.writeFile(imagePath, Buffer.from("fake-image"));
process.env.COMFYUI_URL = "http://comfy.test:8188";
process.env.COMFYUI_WORKFLOW_JSON = workflowPath;
const comfy = await import("./comfyui.js?test=1");

test("generationSpec maps duration to LTX-compatible frame counts", () => {
  assert.deepEqual(comfy.generationSpec(2, "16:9"), {
    width: 704, height: 416, frames: 49, fps: 24, duration: 2, ratio: "16:9"
  });
  assert.deepEqual(comfy.generationSpec(10, "9:16"), {
    width: 416, height: 736, frames: 241, fps: 24, duration: 10, ratio: "9:16"
  });
});

test("deepReplace preserves typed replacement values", () => {
  const out = comfy.deepReplace({text:"hello {{PROMPT}}", width:"{{WIDTH}}", frames:"{{FRAMES}}"}, {
    "{{PROMPT}}":"camera push", "{{WIDTH}}":704, "{{FRAMES}}":49
  });
  assert.deepEqual(out, {text:"hello camera push", width:704, frames:49});
});

test("ComfyUI generation uploads, queues, polls, and downloads a video", async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  let historyCalls = 0;
  globalThis.fetch = async (url, options = {}) => {
    requests.push({url:String(url), options});
    if (String(url).endsWith("/upload/image")) {
      return new Response(JSON.stringify({name:"input.jpg"}), {status:200, headers:{"content-type":"application/json"}});
    }
    if (String(url).endsWith("/prompt")) {
      const body = JSON.parse(String(options.body));
      assert.equal(body.prompt["2"].inputs.text, "camera push");
      assert.equal(body.prompt["3"].inputs.fps, 24);
      return new Response(JSON.stringify({prompt_id:"job-1"}), {status:200, headers:{"content-type":"application/json"}});
    }
    if (String(url).includes("/history/job-1")) {
      historyCalls += 1;
      if (historyCalls === 1) return new Response(JSON.stringify({}), {status:200, headers:{"content-type":"application/json"}});
      return new Response(JSON.stringify({"job-1":{status:{completed:true,status_str:"success"},outputs:{"3":{videos:[{filename:"personal-ai.mp4",subfolder:"",type:"output"}]}}}}), {status:200, headers:{"content-type":"application/json"}});
    }
    if (String(url).includes("/view?")) {
      return new Response(new Uint8Array([0,1,2,3]), {status:200, headers:{"content-type":"video/mp4"}});
    }
    throw new Error("Unexpected fetch: " + url);
  };
  try {
    const buffer = await comfy.generateWithComfyUI({imagePath, prompt:"camera push", duration:2, ratio:"16:9"});
    assert.deepEqual([...buffer], [0,1,2,3]);
    assert.ok(requests.some(request => request.url.endsWith("/prompt")));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("generated workflow contains the expected LTX graph nodes", async () => {
  const raw = await fs.readFile(path.resolve(process.env.COMFYUI_WORKFLOW_JSON), "utf8");
  const workflow = JSON.parse(raw);
  for (const nodeType of ["CLIPLoader","CheckpointLoaderSimple","LTXVImgToVideo","LTXVConditioning","LTXVScheduler","SamplerCustom","VAEDecode","CreateVideo","SaveVideo"]) {
    assert.ok(Object.values(workflow).some(node => node.class_type === nodeType), nodeType + " missing");
  }
});