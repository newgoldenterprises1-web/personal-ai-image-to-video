# Personal AI Image → Video Server

## What it does
- Receives HD source images from the Android app.
- Uploads each source image to Runway Dev using an ephemeral upload.
- Generates image-to-video clips with a real Runway API task.
- Polls task status and downloads the resulting MP4 into local storage.
- Concatenates generated clips with FFmpeg into a final YouTube-ready MP4.
- Keeps the Runway secret on the server, never in the Android APK.

## Requirements
- Node.js 20+
- FFmpeg installed and available as `ffmpeg` on PATH.
- A Runway Dev organization with credits and an API key.

Runway's current API supports Gen-4.5 image-to-video and requires a developer account/API credits. See the official Runway documentation before production use.

## Start
```bash
cd server
npm install
copy .env.example .env
# edit .env and set RUNWAYML_API_SECRET
npm start
```

Linux/macOS:
```bash
cp .env.example .env
```

The API listens on port 8787 by default.

## Android device
If the server runs on your PC and the phone is on the same Wi-Fi:
1. Find the PC's LAN IPv4 address.
2. Set the app Backend URL to `http://YOUR_PC_IP:8787`.
3. Allow Node through the Windows Firewall when prompted.
4. Test `/api/health` from the phone browser.

For a deployed HTTPS server, use the HTTPS URL instead.

## Security
- Never commit `.env`.
- Never put the Runway API key in Flutter.
- This server is intended for personal use. Add authentication and HTTPS before exposing it to the public internet.
