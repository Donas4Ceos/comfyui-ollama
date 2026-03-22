# ============================================================================
# Stage 1: Builder - Download pinned sources and install all Python packages
# ============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Version pins (set in docker-bake.hcl) ----
ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG CIVICOMFY_SHA
ARG RUNPODDIRECT_SHA
ARG COMFYUI_OLLAMA_SHA
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# ---- NVIDIA GPU Detection ----
ARG HAS_NVIDIA_GPU=true

# ---- CUDA variant (set in docker-bake.hcl per target) ----
ARG CUDA_VERSION_DASH=12-8
ARG TORCH_INDEX_SUFFIX=cu128

# Install minimal dependencies needed for building
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    git \
    ca-certificates \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    && if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
         echo "NVIDIA GPU detected - installing CUDA..." && \
         wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
         dpkg -i cuda-keyring_1.1-1_all.deb && \
         apt-get update && \
         apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} libcusparse-dev-${CUDA_VERSION_DASH} && \
         rm cuda-keyring_1.1-1_all.deb; \
       else \
         echo "No NVIDIA GPU - skipping CUDA installation"; \
       fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip and pip-tools for lock file generation
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    python3.12 -m pip install --no-cache-dir pip-tools && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Download pinned source archives
WORKDIR /tmp/build
RUN curl -fSL "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
    mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Manager/archive/${MANAGER_SHA}.tar.gz" -o manager.tar.gz && \
    mkdir -p ComfyUI-Manager && tar xzf manager.tar.gz --strip-components=1 -C ComfyUI-Manager && rm manager.tar.gz && \
    curl -fSL "https://github.com/kijai/ComfyUI-KJNodes/archive/${KJNODES_SHA}.tar.gz" -o kjnodes.tar.gz && \
    mkdir -p ComfyUI-KJNodes && tar xzf kjnodes.tar.gz --strip-components=1 -C ComfyUI-KJNodes && rm kjnodes.tar.gz && \
    curl -fSL "https://github.com/MoonGoblinDev/Civicomfy/archive/${CIVICOMFY_SHA}.tar.gz" -o civicomfy.tar.gz && \
    mkdir -p Civicomfy && tar xzf civicomfy.tar.gz --strip-components=1 -C Civicomfy && rm civicomfy.tar.gz && \
    curl -fSL "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect/archive/${RUNPODDIRECT_SHA}.tar.gz" -o runpoddirect.tar.gz && \
    mkdir -p ComfyUI-RunpodDirect && tar xzf runpoddirect.tar.gz --strip-components=1 -C ComfyUI-RunpodDirect && rm runpoddirect.tar.gz && \
    curl -fSL "https://github.com/stavsap/comfyui-ollama/archive/${COMFYUI_OLLAMA_SHA}.tar.gz" -o comfyui-ollama.tar.gz && \
    mkdir -p ComfyUI-Ollama && tar xzf comfyui-ollama.tar.gz --strip-components=1 -C ComfyUI-Ollama && rm comfyui-ollama.tar.gz

# Init git repos with upstream remotes so ComfyUI-Manager can detect versions
# and users can update via Manager at their own risk
RUN cd /tmp/build/ComfyUI && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && git tag "${COMFYUI_VERSION}" && \
    git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-Manager ${MANAGER_SHA}" && \
    git remote add origin https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-KJNodes && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-KJNodes ${KJNODES_SHA}" && \
    git remote add origin https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd /tmp/build/ComfyUI/custom_nodes/Civicomfy && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Civicomfy ${CIVICOMFY_SHA}" && \
    git remote add origin https://github.com/MoonGoblinDev/Civicomfy.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-RunpodDirect && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-RunpodDirect ${RUNPODDIRECT_SHA}" && \
    git remote add origin https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-Ollama && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-Ollama ${COMFYUI_OLLAMA_SHA}" && \
    git remote add origin https://github.com/stavsap/comfyui-ollama.git

# Install PyTorch (pinned version) - Conditionally based on GPU availability
RUN if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
      echo "Installing PyTorch with CUDA support..." && \
      python3.12 -m pip install --no-cache-dir \
        torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} \
        --index-url https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}; \
    else \
      echo "Installing PyTorch CPU version..." && \
      python3.12 -m pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cpu; \
    fi

# Generate lock file from all requirements, then install with hash verification
WORKDIR /tmp/build
RUN cat ComfyUI/requirements.txt > requirements.in && \
    for node_dir in ComfyUI/custom_nodes/*/; do \
        if [ -f "$node_dir/requirements.txt" ]; then \
            # Fix ComfyUI-Ollama: 'dotenv' is not on PyPI, correct package is 'python-dotenv' \
            sed -i 's/^dotenv$/python-dotenv/' "$node_dir/requirements.txt"; \
            # Ensure trailing newline so packages don't concatenate when appended \
            echo "" >> "$node_dir/requirements.txt"; \
            cat "$node_dir/requirements.txt" >> requirements.in; \
        fi; \
    done && \
    echo "GitPython" >> requirements.in && \
    echo "opencv-python" >> requirements.in && \
    echo "jupyter" >> requirements.in && \
    echo "jupyter-resource-usage" >> requirements.in && \
    echo "jupyterlab-nvdashboard" >> requirements.in && \
    echo "torch==${TORCH_VERSION}" >> constraints.txt && \
    echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
    echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
    echo "pillow>=12.1.1" >> constraints.txt && \
    PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
    python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# Pre-populate ComfyUI-Manager cache so first cold start skips the slow registry fetch
COPY scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI + custom nodes into a known location for runtime copy
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# ============================================================================
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV FILEBROWSER_CONFIG=/workspace/runpod-slim/.filebrowser.json
ENV OLLAMA_MODELS=/workspace/ollama-models
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_BASE_URL=http://localhost:11434
ENV OLLAMA_KEEP_ALIVE=10m
ENV WEBUI_PORT=3000
# WEBUI_SECRET_KEY is intentionally NOT set here — generated at runtime by start.sh for security
ENV DATA_DIR=/workspace/open-webui/data
ENV ENABLE_OLLAMA_API=True
ENV OLLAMA_API_BASE_URL=http://localhost:11434/api

# ---- NVIDIA GPU Detection (re-declared for runtime stage) ----
ARG HAS_NVIDIA_GPU=true

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=12-8

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256

# Update and install runtime dependencies, CUDA, and common tools
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    libssl-dev \
    wget \
    gnupg \
    xz-utils \
    zstd \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    openssl \
    ffmpeg \
    && if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
         echo "NVIDIA GPU detected - installing CUDA runtime..." && \
         wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
         dpkg -i cuda-keyring_1.1-1_all.deb && \
         apt-get update && \
         apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} && \
         rm cuda-keyring_1.1-1_all.deb; \
       else \
         echo "No NVIDIA GPU - skipping CUDA runtime installation"; \
       fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Copy Python packages, executables, and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
    echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
    > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# Copy baked ComfyUI + custom nodes from builder stage
COPY --from=builder /opt/comfyui-baked /opt/comfyui-baked

# Remove uv to force ComfyUI-Manager to use pip (uv doesn't respect --system-site-packages properly)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Install FileBrowser (pinned version with checksum)
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
    echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    rm /tmp/fb.tar.gz

# Install Ollama for serving LLMs
ENV OLLAMA_VERSION=0.18.2
RUN curl -fSL --retry 5 --retry-delay 3 "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" -o /tmp/ollama.tar.zst && \
    mkdir -p /tmp/ollama_extract && \
    tar -I zstd -xf /tmp/ollama.tar.zst -C /tmp/ollama_extract && \
    find /tmp/ollama_extract -name "ollama" -type f -exec mv {} /usr/local/bin/ollama \; && \
    chmod +x /usr/local/bin/ollama && \
    rm -rf /tmp/ollama*

# Install Node.js 22.x for Open WebUI
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install essential tools (split for granular caching)
RUN apt-get update && apt-get install -y --no-install-recommends unzip zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends rclone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends aria2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Open WebUI — patch the wheel to bypass yanked ddgs==9.11.2 pin
ENV OPEN_WEBUI_VERSION=0.8.10
WORKDIR /tmp/webui_patch
RUN python3.12 -m pip download --no-deps open-webui==${OPEN_WEBUI_VERSION}

RUN unzip open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl -d content && \
    python3.12 -c "import os; f='content/open_webui-${OPEN_WEBUI_VERSION}.dist-info/METADATA'; t=open(f).read(); t=t.replace('ddgs==9.11.2', 'ddgs>=9.11.3').replace('ddgs ==9.11.2', 'ddgs>=9.11.3').replace('ddgs (==9.11.2)', 'ddgs (>=9.11.3)'); open(f,'w').write(t)" && \
    cd content && zip -q -r ../open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl * && \
    cd .. && rm -rf content

RUN python3.12 -m pip install --no-cache-dir ./open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl ddgs==9.11.3 starlette-compress && \
    rm -rf /tmp/webui_patch

# Install professional monitoring tools (granular layers)
WORKDIR /workspace/runpod-slim
RUN python3.12 -m pip install --no-cache-dir nvitop
RUN python3.12 -m pip install --no-cache-dir gpustat && \
    ln -s /usr/local/bin/gpustat /usr/bin/gpustat
RUN python3.12 -m pip install --no-cache-dir gpustat-web

# Set CUDA environment variables (only if GPU is available)
RUN if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
      echo "export PATH=/usr/local/cuda/bin:\${PATH}" >> /etc/environment && \
      echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64" >> /etc/environment && \
      echo "alias gpu='nvitop'" >> /etc/bash.bashrc; \
    fi

ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Jupyter is included in the lock file and installed in the builder stage

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    rm -f /etc/ssh/ssh_host_*

# Create workspace directory
RUN mkdir -p /workspace/runpod-slim
WORKDIR /workspace/runpod-slim

# Install code-server
RUN curl -fsSL --retry 5 --retry-delay 5 https://code-server.dev/install.sh | sh

# Install AriaNg (Aria2 Web UI)
RUN mkdir -p /opt/ariang && \
    curl -fSL "https://github.com/mayswind/AriaNg/releases/download/1.3.13/AriaNg-1.3.13-AllInOne.zip" -o /tmp/ariang.zip && \
    unzip /tmp/ariang.zip -d /opt/ariang && \
    rm /tmp/ariang.zip

# Expose ports
# 8188: ComfyUI, 22: SSH, 8888: Jupyter, 8080: FileBrowser, 11434: Ollama, 3000: OpenWebUI, 8443: CodeServer, 8081: AriaNg, 6800: Aria2 RPC, 5572: Rclone GUI, 4000: GPU Stat Web
EXPOSE 8188 22 8888 8080 11434 3000 8443 8081 6800 5572 4000

# Health check — ComfyUI HTTP endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost:8188 || exit 1

# Copy start script
COPY start.sh /start.sh

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

ENTRYPOINT ["/start.sh"]
