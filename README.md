# Personal AI Image → Video Studio

Personal-use Android app for turning multiple HD images into AI-animated scene clips and combining them into a final MP4 for YouTube.

## Scope lock
- no login
- no payments
- no subscriptions
- no marketplace
- no social feed
- no public profiles
- Android only
- image → AI video → final MP4

## Architecture
Android Flutter app → personal Node.js backend → local ComfyUI/open image-to-video model → local FFmpeg renderer → final MP4.

The backend keeps local ComfyUI and FFmpeg off the Android app and provides a single local generation/render endpoint.

## Current real generation path
1. Android imports the original selected image and stores a private app copy without intentional image-quality downscaling.
2. Android uploads the image to the personal backend.
3. Backend sends the image and prompt to a **local ComfyUI instance running on the user's own PC**.
4. ComfyUI runs an open image-to-video workflow and returns the generated video locally.
5. The backend stores the generated MP4 in project storage.
6. The Android app polls the job until completion and stores the generated clip URL.
7. After the required scenes are ready, the backend validates the clip paths and uses local FFmpeg to create the final export.
8. The final export is normalized to the selected canvas, with 1080p as the default target and H.264/AAC MP4 output.

**No paid cloud AI API, API key, subscription, payment gateway, or per-generation charge is required.** The AI model runs locally through ComfyUI. The trade-off is that generation requires a capable PC/GPU and local model files.

To generate video, place an API-format ComfyUI workflow JSON at `server/workflows/image-to-video.json` or point `COMFYUI_WORKFLOW_JSON` to your own workflow file.

## USB test path

With USB debugging enabled on the Android phone and the backend running on the PC, use `adb reverse tcp:8787 tcp:8787` and keep the app backend URL at `http://127.0.0.1:8787`.
