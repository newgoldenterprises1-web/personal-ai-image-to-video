# Personal AI Image → Video backend

This backend is intentionally free of paid AI APIs. It uses local ComfyUI with a user-provided API-format workflow, then local FFmpeg for final MP4 rendering.

## Free local setup

1. Install Node.js 20+ and FFmpeg.
2. Install ComfyUI on the same PC.
3. Add an API-format image-to-video workflow JSON to `server/workflows/image-to-video.json`, or point `COMFYUI_WORKFLOW_JSON` at your own workflow file.
4. Start ComfyUI on `http://127.0.0.1:8188`.
5. Copy `server/.env.example` to `server/.env` when needed.
6. Run:

```bash
npm install
npm start
```

## Generation flow

- Android uploads the original selected image.
- Node sends it to the local ComfyUI input store.
- The backend injects the scene prompt, ratio, dimensions, frame count, FPS, and a fresh seed into the local API workflow.
- ComfyUI runs the image-to-video graph locally.
- The backend polls ComfyUI history until a real MP4/WebM/MOV/MKV video output exists.
- The generated scene clip is stored under the project `clips/` directory.
- Final multi-scene rendering uses local FFmpeg and produces 720p or 1080p MP4.

## USB Android connection

For a physical Android phone connected by USB with USB debugging enabled:

```bash
adb reverse tcp:8787 tcp:8787
```

Set the app backend URL to:

```text
http://127.0.0.1:8787
```

The Android app does not use a paid cloud endpoint.

## Model and quality notes

The exact model or workflow you use depends on the ComfyUI graph you install. Generated AI frames can be an upscale relative to the final YouTube canvas, while final export can still be 1080p through FFmpeg.

Verify the license of the exact model files and workflow you install before commercial YouTube publishing.

## Hardware note

No API credits or subscription are required for local inference. Local inference still requires enough GPU/VRAM, RAM, disk space, and time for the selected model. Physics remains stubbornly non-free.

## Windows preflight

From the repository root, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-local-ai.ps1
```

Do this before testing the Android app. It checks the local ComfyUI server, LTXV node registration, model files, FFmpeg, and the API-format workflow.

The repository intentionally does not contain large model weights. The included workflow references the LTX-Video 0.9.5 2B checkpoint and `t5xxl_fp16.safetensors`. Download those separately into the ComfyUI model directories and review their exact license terms before commercial use.

## Convenience scripts

From the repository root on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-local-ai.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start-backend.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\connect-android-usb.ps1
```

Use the readiness checker first, then start the backend, then create the USB reverse tunnel. The Android app should use `http://127.0.0.1:8787`.

## Hardware expectations

The bundled LTX-Video 0.9.5 2B path is a local GPU workload. Current ComfyUI model guidance lists about 12 GB VRAM minimum and 16 GB recommended for the 2B model, with 32 GB system RAM recommended for LTX workflows. Actual usage varies with resolution, frame count, batching, and optimization settings.

The model files are large and are intentionally not committed to GitHub. The LTX checkpoint is about 6.34 GB and the referenced T5 FP16 encoder is about 9.79 GB, so allow substantial disk space for local model storage.
