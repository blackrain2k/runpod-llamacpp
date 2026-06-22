#!/bin/bash
set -euo pipefail

# =============================================================================
# Startup Script — Tailscale + llama.cpp server
# =============================================================================
# Runs inside the RunPod container.
# Environment variables are set in the RunPod template configuration.
# =============================================================================

log() { echo "[start] $*"; }

# --- Tailscale ---
log "Setting up Tailscale..."

mkdir -p /var/lib/tailscale /var/run/tailscale

# Start tailscaled in background
tailscaled \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --port=41641 &
TAILSCALED_PID=$!

sleep 3

if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
    log "Authenticating with Tailscale..."
    tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TAILSCALE_HOSTNAME:-runpod-llamacpp}" \
        --accept-routes \
        --reset 2>&1 || true

    log "Waiting for Tailscale to connect..."
    for i in $(seq 1 30); do
        if tailscale status --json 2>/dev/null | jq -e '.Self.Online' 2>/dev/null; then
            TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
            log "Tailscale online at ${TAILSCALE_IP}"
            break
        fi
        [ $i -eq 30 ] && log "WARNING: Tailscale not online after 60s, continuing anyway..."
        sleep 2
    done
else
    log "No TAILSCALE_AUTH_KEY — skipping Tailscale authentication"
    log "Container will be accessible via RunPod's public IP only"
fi

# --- Model Download (optional, if model not present) ---
MODEL_PATH="${MODEL_PATH:-/workspace/models/model.gguf}"

if [ ! -f "$MODEL_PATH" ]; then
    if [ -n "${MODEL_URL:-}" ] || [ -n "${HF_REPO:-}" ]; then
        log "Model not found at ${MODEL_PATH}, downloading..."
        download-model || {
            log "ERROR: Model download failed. Exiting."
            exit 1
        }
    else
        log "ERROR: Model not found at ${MODEL_PATH} and no download source configured."
        log "Set MODEL_URL or HF_REPO+HF_FILE in the template environment."
        exit 1
    fi
fi

# --- llama.cpp Server ---
log "Starting llama.cpp server..."

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
NGPULAYERS="${NGPULAYERS:-99}"
ALIAS="${ALIAS:-llamacpp}"
CONTEXT="${CONTEXT:-128000}"
THREADS="${THREADS:-$(nproc)}"
FLASH_ATTN="${FLASH_ATTN:-1}"

# Build server arguments
SERVER_ARGS=(
    --model "$MODEL_PATH"
    --host "$HOST"
    --port "$PORT"
    --n-gpu-layers "$NGPULAYERS"
    --alias "$ALIAS"
    --ctx-size "$CONTEXT"
    --threads "$THREADS"
)

# Flash attention (recommended for modern GPUs)
if [ "$FLASH_ATTN" = "1" ]; then
    SERVER_ARGS+=(--flash-attn)
fi

# No-mmap: avoids hangs when loading from network storage
if [ "${NO_MMAP:-1}" = "1" ]; then
    SERVER_ARGS+=(--no-mmap)
fi

# Extra args from env (space-separated)
if [ -n "${LLAMACPP_EXTRA_ARGS:-}" ]; then
    read -r -a EXTRA <<< "$LLAMACPP_EXTRA_ARGS"
    SERVER_ARGS+=("${EXTRA[@]}")
fi

log "Server args: ${SERVER_ARGS[*]}"
log "Model: ${MODEL_PATH}"
log "GPU layers: ${NGPULAYERS}, Context: ${CONTEXT}, Threads: ${THREADS}"

exec llama-server "${SERVER_ARGS[@]}"