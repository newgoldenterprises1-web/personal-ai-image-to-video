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

**No Runway API, API key, subscription, payment gateway, or paid generation service is required.** The AI model runs locally. The trade-off is that generation requires a capable PC/GPU and local model files. The app itself has no subscription or per-generation charge. Local inference does not call a paid cloud AI API.

`ComfyUI` is an open local UI/server that can run open image-to-video models such as LTX-Video or Wan-family workflows. Model licenses and hardware requirements vary by model, so the selected workflow must be checked before commercial use.