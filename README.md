# Personal AI Image → Video Studio

Personal-use Android app for turning multiple HD images into AI-animated scene clips and combining them into a final MP4 for YouTube.

## Scope lock
This project is intentionally narrow:
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

The backend is required because the Runway API secret must not be embedded in the Android application.

## Current generation path
Each scene:
1. Android preserves the selected source image in app storage without intentional downscaling.
2. App uploads the image to the personal backend.
3. Backend uses Runway ephemeral upload and creates an image-to-video task.
4. Backend polls the task and downloads the ephemeral result to local storage.
5. After all scenes are ready, FFmpeg concatenates them and produces a 1080p MP4 target.

Runway currently documents Gen-4.5 image-to-video and 4/5/6/8 second generation durations. Longer 5–7 minute YouTube videos are therefore built from many short scene clips, not one giant AI generation.

## Android setup
Install Flutter, then:
```bash
flutter pub get
flutter run
```
Use an Android phone with USB debugging enabled.

## Backend setup
```bash
cd server
npm install
copy .env.example .env
npm start
```
Install FFmpeg and ensure `ffmpeg -version` works.

Set the app Backend URL:
- Android emulator: `http://10.0.2.2:8787`
- Physical phone on same Wi-Fi: `http://PC_LAN_IP:8787`

## Important
A real generation cannot be tested without a valid Runway API key and credits. The code intentionally fails clearly when the server is not configured instead of pretending a fake render is an AI result.
