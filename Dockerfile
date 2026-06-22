# =============================================================================
# RunPod llama.cpp + Tailscale — Multi-stage Dockerfile
# =============================================================================
# Build stage: compiles llama.cpp with CUDA support
# Runtime stage: lean image with binaries + Tailscale
#
# Target GPU: RTX PRO 6000 Blackwell (sm_120, 96GB VRAM)
# Adjust CUDA_ARCHITECTURES for other GPUs (see README)
# =============================================================================

# ---- Build Stage ----
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS builder

ARG LLAMACPP_REF=master
ARG CUDA_ARCHITECTURES=120
ARG BUILD_THREADS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Clone llama.cpp (branch, tag, or commit hash)
RUN git clone --depth 1 ${LLAMACPP_REF:+--branch }${LLAMACPP_REF} \
    https://github.com/ggml-org/llama.cpp.git /opt/llama.cpp

# Build with CUDA
# GGML_CUDA=ON enables GPU acceleration
# CMAKE_CUDA_ARCHITECTURES targets specific GPU (120 = Blackwell sm_120)
# GGML_NATIVE=OFF for cross-compilation (we're building without GPU access)
RUN cd /opt/llama.cpp && \
    if [ "$BUILD_THREADS" = "0" ]; then \
        BUILD_THREADS=$(nproc); \
    fi && \
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DGGML_NATIVE=OFF \
        -DLLAMA_CURL=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -j${BUILD_THREADS}

# ---- Runtime Stage ----
FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

LABEL org.opencontainers.image.title="runpod-llamacpp"
LABEL org.opencontainers.image.description="llama.cpp server with Tailscale for RunPod"
LABEL org.opencontainers.image.source="https://github.com/nettohotel/runpod-llamacpp"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    python3 \
    python3-pip \
    iptables \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list" \
        -o /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends tailscale && \
    rm -rf /var/lib/apt/lists/*

# Copy llama.cpp binaries from builder
COPY --from=builder /opt/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /opt/llama.cpp/build/bin/llama-cli /usr/local/bin/llama-cli

# Verify binary
RUN llama-server --version || true

# Copy scripts
COPY start.sh /start.sh
COPY scripts/download-model.sh /usr/local/bin/download-model
RUN chmod +x /start.sh /usr/local/bin/download-model

# Create Tailscale state directory (persisted via volume)
RUN mkdir -p /var/lib/tailscale /var/run/tailscale

WORKDIR /workspace

EXPOSE 8080

CMD ["/start.sh"]