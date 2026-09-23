# Personal AI Image → Video backend

This backend is intentionally **free of paid AI APIs**. It uses a local ComfyUI server and local open image-to-video workflows, then FFmpeg for final MP4 rendering.

## Setup

1. Install Node.js 20+ and FFmpeg.
2. Install ComfyUI on the same PC and install an image-to-video workflow/model.
3. Export the ComfyUI workflow in API format to `server/workflows/image-to-video.json`.
4. In that workflow, use these placeholders where applicable:
   - `{{IMAGE}}` for the uploaded input image filename
   - `{{PROMPT}}` for the scene prompt
   - `{{DURATION}}` for the requested duration
   - `{{RATIO}}` for the project ratio
5. Start ComfyUI on `http://127.0.0.1:8188`.
6. Configure `server/.env` from `.env.example`.
7. Run `npm install` then `npm start`.

The backend uploads the selected image to local ComfyUI, queues the workflow, waits for completion, downloads the first returned video/gif/image output, and stores it as an MP4 scene clip.

## Important free-use note

There is no Runway API key, subscription, or per-generation API charge in this architecture. Compute is local, so there is no cloud inference bill. Your PC electricity and hardware are, tragically, still subject to the laws of physics.

Model licenses differ. Before using generated media commercially on YouTube, verify the license of the exact model and workflow you installed.
