# Personal AI Image → Video backend

This backend is intentionally free of paid AI APIs. It uses local ComfyUI with the built-in LTX-Video workflow path, then local FFmpeg for final MP4 rendering.

## Free local setup

1. Install Node.js 20+ and FFmpeg.
2. Install a recent ComfyUI build with the LTXV nodes available.
3. Download `ltx-video-2b-v0.9.5.safetensors` into `ComfyUI/models/checkpoints/`.
4. Download `t5xxl_fp16.safetensors` into `ComfyUI/models/text_encoders/`.
5. Keep the included API-format workflow at `server/workflows/image-to-video.json`.
6. Start ComfyUI on `http://127.0.0.1:8188`.
7. Copy `server/.env.example` to `server/.env` when needed.
8. Run:

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

The bundled workflow targets the LTX-Video 0.9.5 2B checkpoint. Its practical workflow range is kept below 257 frames and uses 24 FPS, while final export can still be 1080p through FFmpeg. Generated AI frames can therefore be an upscale relative to the final YouTube canvas.

Verify the exact license of the checkpoint and any additional model files before commercial YouTube publishing. The LTX-Video 0.9.5 release notes describe a commercial-use license change, but license terms can differ across model releases.

## Hardware note

No API credits or subscription are required for local inference. Local inference still requires enough GPU/VRAM, RAM, disk space, and time for the selected model. Physics remains stubbornly non-free.