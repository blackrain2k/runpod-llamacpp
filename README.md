# runpod-llamacpp

Docker image for deploying **llama.cpp** with **Tailscale** on RunPod Pods.

## Architecture

```
GitHub repo ──push──► GitHub Actions ──build──► GHCR (ghcr.io)
                                                    │
                                              RunPod Pod
                                              (custom template)
                                                    │
                                     ┌──────────────┼──────────────┐
                                     ▼              ▼              ▼
                                Tailscale    llama-server    Network Volume
                                (VPN mesh)   (LLM API :8080) (/workspace/models/)
```

## What's inside

- **llama.cpp** compiled with CUDA support (GPU acceleration)
- **Tailscale** for secure mesh VPN access
- **Startup script** that:
  1. Starts Tailscale daemon + authenticates
  2. Downloads model if not present (from URL or HuggingFace)
  3. Launches `llama-server` with configurable parameters

## Prerequisites

1. **GitHub account** with the repo pushed
2. **RunPod account** with API access
3. **Tailscale account** — generate an auth key at
   [Tailscale Admin → Settings → Keys](https://login.tailscale.com/admin/settings/keys)
4. **RunPod Network Volume** (200+ GB) for model storage — mounted at `/workspace`

## GPU Architecture

The Dockerfile targets **sm_120** (Blackwell: RTX PRO 6000, RTX 5090, etc.)
with CUDA 12.8.1.

For other GPUs, change `CUDA_ARCHITECTURES` build arg:

| GPU              | Architecture | Value |
|------------------|-------------|-------|
| RTX PRO 6000 Blackwell | Blackwell | `120` |
| RTX 5090 / 5080  | Blackwell   | `120` |
| H100 / H200      | Hopper      | `90`  |
| RTX 4090 / 4080  | Ada         | `89`  |
| A100             | Ampere      | `80`  |
| RTX 3090         | Ampere      | `86`  |
| V100             | Volta       | `70`  |

## Build & Deploy

### 1. Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit: llama.cpp + Tailscale for RunPod"
git remote add origin git@github.com:YOUR_USER/runpod-llamacpp.git
git push -u origin main
```

### 2. GitHub Actions builds automatically

On push to `main`, the workflow:
- Builds the Docker image (multi-stage: compile llama.cpp → slim runtime)
- Pushes to `ghcr.io/YOUR_USER/runpod-llamacpp:latest`
- Uses GitHub Actions cache for faster rebuilds

Monitor: **Actions** tab in your GitHub repo.
First build: ~20-30 min (CUDA compilation). Rebuilds: ~5 min (cache).

### 3. Create RunPod Template

1. Go to [RunPod Console → Pods → Deploy](https://console.runpod.io/pods)
2. Select **Custom Template** (or "Deploy Custom Template")
3. Set **Image** to: `ghcr.io/YOUR_USER/runpod-llamacpp:latest`
4. Select GPU type (e.g., RTX PRO 6000)
5. Attach **Network Volume** (mounted at `/workspace`)
6. Set environment variables (see below)
7. Expose port **8080** (HTTP)
8. Deploy

### 4. Environment Variables

Set these in the RunPod template:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TAILSCALE_AUTH_KEY` | **Yes** | — | Tailscale auth key (`tskey-...`) |
| `TAILSCALE_HOSTNAME` | No | `runpod-llamacpp` | Tailscale hostname |
| `MODEL_PATH` | No | `/workspace/models/model.gguf` | Path to GGUF model |
| `MODEL_URL` | No* | — | Direct URL to GGUF file |
| `HF_REPO` | No* | `Qwen/Qwen2.5-32B-Instruct-GGUF` | HuggingFace repo ID |
| `HF_FILE` | No* | `qwen2.5-32b-instruct-q8_0.gguf` | HuggingFace filename |
| `HF_TOKEN` | No | — | HuggingFace token (for gated models) |
| `PORT` | No | `8080` | Server listen port |
| `NGPULAYERS` | No | `99` | GPU layers to offload |
| `ALIAS` | No | `llamacpp` | Server alias (for Hermes) |
| `CONTEXT` | No | `128000` | Context window size |
| `FLASH_ATTN` | No | `1` | Enable flash attention |
| `NO_MMAP` | No | `1` | Disable mmap (fixes network storage hangs) |
| `LLAMACPP_EXTRA_ARGS` | No | — | Extra args passed to llama-server |

\* Either `MODEL_URL` **or** `HF_REPO`+`HF_FILE` needed if model is not pre-placed on the network volume.

### 5. Model Storage Strategy

**Recommended:** Pre-place the model on the network volume.

```bash
# On a running pod with the volume attached:
mkdir -p /workspace/models
# Download directly (from another pod or via SSH):
wget -O /workspace/models/model.gguf "https://huggingface.co/Qwen/Qwen2.5-32B-Instruct-GGUF/resolve/main/qwen2.5-32b-instruct-q8_0.gguf"
```

This way the startup script finds the model and skips download — pod is ready in seconds instead of 15+ minutes.

If the model is missing, the script downloads it automatically on first boot (requires `MODEL_URL` or `HF_REPO`+`HF_FILE`).

## Tailscale Notes

- The container starts `tailscaled` in userspace mode
- Auth key should be **ephemeral** (cleaned up when pod stops) or **reusable**
- Tailscale state is stored at `/var/lib/tailscale/` — if you want persistence across restarts, mount a volume there
- The pod will be accessible at `100.x.x.x:8080` from any device on your Tailscale network

## Local Testing

```bash
# Build (requires Docker with buildkit)
docker build -t runpod-llamacpp --build-arg CUDA_ARCHITECTURES=120 .

# Run (requires NVIDIA container runtime)
docker run --gpus all \
  -e TAILSCALE_AUTH_KEY=tskey-... \
  -e MODEL_PATH=/workspace/models/model.gguf \
  -v /path/to/models:/workspace/models \
  -p 8080:8080 \
  runpod-llamacpp
```

## File Structure

```
runpod-llamacpp/
├── Dockerfile                    # Multi-stage: build llama.cpp → slim runtime
├── start.sh                      # Startup: Tailscale → model check → llama-server
├── scripts/
│   └── download-model.sh         # GGUF downloader (URL or HuggingFace)
├── .github/workflows/
│   └── build-image.yml           # GitHub Actions → build → push to GHCR
├── .env.example                  # Template for environment variables
├── .gitignore
└── README.md                     # This file
```

## Customization

### Change llama.cpp version

Set repo variable `LLAMACPP_VERSION` in GitHub:
**Settings → Secrets and variables → Actions → Variables**

Check available tags: https://github.com/ggml-org/llama.cpp/releases

### Change GPU target

Set repo variable `CUDA_ARCHITECTURES` (see table above).

### Add custom server flags

Set `LLAMACPP_EXTRA_ARGS` in the RunPod template, e.g.:
```
LLAMACPP_EXTRA_ARGS=--no-context-shift --temp 0.7 --top-k 40
```