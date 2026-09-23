# Personal AI Image → Video — Project Lock

## Repository lock
All development for this project is restricted to this repository:
`newgoldenterprises1-web/personal-ai-image-to-video`

Do not create, modify, or continue this project in another repository.

## Product scope
Personal-use Android application for creating videos from images.

Included:
- Image import
- HD image handling
- Image ordering and scene editing
- AI image-to-video generation
- HD video generation
- 1080p export target
- MP4 preview/export
- YouTube-oriented output quality

Explicitly excluded:
- Login/authentication
- Payment gateway
- Subscriptions
- Marketplace
- Social feed
- Public profiles
- Unrelated features

## Quality requirement
Do not intentionally downscale source images.
Preserve the highest practical source quality through the generation/render pipeline.
1080p is the default final export target, with the renderer configured to avoid unnecessary recompression.

## Development rule
Do not declare the project complete based only on UI. Completion requires the real frontend, backend, AI generation path, rendering pipeline, error handling, and a verified build/run path.
