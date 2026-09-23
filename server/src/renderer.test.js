import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { safeOutputName, sceneToAbsolute } from "./renderer.js";

test("safeOutputName prevents unsafe output names", () => {
  assert.equal(safeOutputName("../../final video"), "______final_video.mp4");
  assert.equal(safeOutputName("youtube.mp4"), "youtube.mp4");
});

test("sceneToAbsolute accepts only files inside project storage", () => {
  const root = path.resolve("/tmp/personal-ai-video-data");
  const valid = sceneToAbsolute(root, {
    videoPath: path.join(root, "projects", "p1", "clips", "a.mp4")
  });
  assert.ok(valid.startsWith(root + path.sep));

  assert.throws(
    () => sceneToAbsolute(root, {
      videoPath: path.join(root, "..", "secret.mp4")
    }),
    /videoPath or videoUrl/
  );

  assert.throws(
    () => sceneToAbsolute(root, {
      videoUrl: "https://evil.example/media/../../secret.mp4"
    }),
    /videoPath or videoUrl/
  );
});
