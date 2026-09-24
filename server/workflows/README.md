# Local ComfyUI workflow

Place an API-format ComfyUI workflow JSON here at:

```text
server/workflows/image-to-video.json
```

The backend expects the workflow to include placeholders that it can replace before queuing a job:

- `{{IMAGE}}`
- `{{PROMPT}}`
- `{{DURATION}}`
- `{{RATIO}}`
- `{{WIDTH}}`
- `{{HEIGHT}}`
- `{{FRAMES}}`
- `{{FPS}}`
- `{{SEED}}`

The exact node graph depends on the open image-to-video model you install in ComfyUI. Keep the workflow local, keep it free, and keep it compatible with your GPU. Humans do love a system that is both simple in concept and oddly specific in practice.
