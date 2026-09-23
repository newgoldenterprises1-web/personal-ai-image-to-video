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
Android Flutter app → personal Node.js backend → Runway Dev image-to-video → local FFmpeg renderer → final MP4.

The backend is required because the Runway API secret must never be embedded in the Android application.

## Current real generation path
1. Android imports the original selected image and stores a private app copy without intentional image-quality downscaling.
2. Android uploads the image to the personal backend.
3. Backend uses a Runway ephemeral upload.
4. Backend creates a real Runway Gen-4.5 image-to-video task.
5. Backend polls the task and downloads the generated MP4 into project storage.
6. The Android app polls the job until completion and stores the generated clip URL.
7. After the required scenes are ready, the backend validates the clip paths and uses FFmpeg to create the final export.
8. The final export is normalized to the selected canvas, with 1080p as the default target and H.264/AAC MP4 output.

Runway's current Gen-4.5 API supports image-to-video durations from 2–10 seconds. Long YouTube videos are built from multiple scene clips rather than one giant AI generation.

## Quality and aspect ratios
Runway Gen-4.5 image-to-video currently supports:
- landscape: 1280:720
- portrait: 720:1280
- square: 960:960

The app preserves source images as imported and only performs the final video encoding/scaling required by the selected export canvas. A 1080p final export from a 1280×720 Gen-4.5 source is an upscale during final rendering, not a claim that Gen-4.5 itself produced native 1920×1080 pixels.

## Android setup
Install Flutter, then run:

    flutter pub get
    flutter run

Use an Android phone with USB debugging enabled.

Backend URL:
- Android emulator: http://10.0.2.2:8787
- Physical phone on the same Wi-Fi: http://PC_LAN_IP:8787

The Android manifest includes Internet permission and cleartext HTTP support for local development.

## Backend setup
    cd server
    npm install
    copy .env.example .env
    npm start

Install FFmpeg and verify with ffmpeg -version.

Set RUNWAYML_API_SECRET in server/.env. Never put that secret in Flutter source code.

## Validation
GitHub Actions runs Flutter dependencies, backend smoke tests, flutter analyze, flutter test, and a release APK build.

A real AI generation requires a valid Runway API secret and available Runway credits. The application deliberately reports a clear configuration error when the backend is not configured instead of faking an AI result.
