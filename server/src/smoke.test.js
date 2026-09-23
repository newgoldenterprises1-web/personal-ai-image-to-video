import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

test("server source files exist", () => {
  assert.ok(fs.existsSync(path.join(process.cwd(), "src", "index.js")));
  assert.ok(fs.existsSync(path.join(process.cwd(), "src", "renderer.js")));
});
