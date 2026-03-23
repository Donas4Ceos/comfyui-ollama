# ============================================================================
# STAGE 1: base-system - Ubuntu + apt minimum
# ============================================================================
FROM ubuntu:24.04 AS base-system

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    gnupg \
    xz-utils \
    zstd \
    git \
    build-essential \
    rustc \
    cargo \
    libssl-dev \
    nano \
    htop \
    tmux \
    less \
    net-tools \
    iputils-ping \
    procps \
    openssl \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STAGE 2: base-cuda - NVIDIA CUDA (conditional)
# ============================================================================
FROM base-system AS base-cuda

ARG CUDA_VERSION_DASH=12-8
ARG HAS_NVIDIA_GPU=true

RUN if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
    echo "Installing CUDA ${CUDA_VERSION_DASH}..." && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} && \
    rm cuda-keyring_1.1-1_all.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# ============================================================================
# STAGE 3: python-base - Python 3.12 + pip
# ============================================================================
FROM base-cuda AS python-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    rm get-pip.py

ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64
ENV PYTHONUNBUFFERED=1

# ============================================================================
# STAGE 4: comfyui-core - ComfyUI + custom nodes
# ============================================================================
FROM python-base AS comfyui-core

ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG CIVICOMFY_SHA
ARG RUNPODDIRECT_SHA
ARG COMFYUI_OLLAMA_SHA
ARG IMPACT_PACK_SHA
ARG VIDEOHELPERSUITE_SHA

WORKDIR /tmp/build

# Download ComfyUI
RUN curl -fSL "https://github.com/Comfy-Org/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
    mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

# Download custom nodes
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Manager/archive/${MANAGER_SHA}.tar.gz" -o manager.tar.gz && \
    mkdir -p ComfyUI-Manager && tar xzf manager.tar.gz --strip-components=1 -C ComfyUI-Manager && rm manager.tar.gz

RUN curl -fSL "https://github.com/kijai/ComfyUI-KJNodes/archive/${KJNODES_SHA}.tar.gz" -o kjnodes.tar.gz && \
    mkdir -p ComfyUI-KJNodes && tar xzf kjnodes.tar.gz --strip-components=1 -C ComfyUI-KJNodes && rm kjnodes.tar.gz

RUN curl -fSL "https://github.com/MoonGoblinDev/Civicomfy/archive/${CIVICOMFY_SHA}.tar.gz" -o civicomfy.tar.gz && \
    mkdir -p Civicomfy && tar xzf civicomfy.tar.gz --strip-components=1 -C Civicomfy && rm civicomfy.tar.gz

RUN curl -fSL "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect/archive/${RUNPODDIRECT_SHA}.tar.gz" -o runpoddirect.tar.gz && \
    mkdir -p ComfyUI-RunpodDirect && tar xzf runpoddirect.tar.gz --strip-components=1 -C ComfyUI-RunpodDirect && rm runpoddirect.tar.gz

RUN curl -fSL "https://github.com/stavsap/comfyui-ollama/archive/${COMFYUI_OLLAMA_SHA}.tar.gz" -o comfyui-ollama.tar.gz && \
    mkdir -p ComfyUI-Ollama && tar xzf comfyui-ollama.tar.gz --strip-components=1 -C ComfyUI-Ollama && rm comfyui-ollama.tar.gz

RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Impact-Pack/archive/${IMPACT_PACK_SHA}.tar.gz" -o impact.tar.gz && \
    mkdir -p ComfyUI-Impact-Pack && tar xzf impact.tar.gz --strip-components=1 -C ComfyUI-Impact-Pack && rm impact.tar.gz

RUN curl -fSL "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite/archive/${VIDEOHELPERSUITE_SHA}.tar.gz" -o vhs.tar.gz && \
    mkdir -p ComfyUI-VideoHelperSuite && tar xzf vhs.tar.gz --strip-components=1 -C ComfyUI-VideoHelperSuite && rm vhs.tar.gz

# Init git repos for ComfyUI-Manager updates
WORKDIR /tmp/build/ComfyUI
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && \
    git tag "${COMFYUI_VERSION}" && \
    git remote add origin https://github.com/Comfy-Org/ComfyUI.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-Manager
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Manager ${MANAGER_SHA}" && \
    git remote add origin https://github.com/ltdrdata/ComfyUI-Manager.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-KJNodes
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "KJNodes ${KJNODES_SHA}" && \
    git remote add origin https://github.com/kijai/ComfyUI-KJNodes.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/Civicomfy
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Civicomfy ${CIVICOMFY_SHA}" && \
    git remote add origin https://github.com/MoonGoblinDev/Civicomfy.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-RunpodDirect
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "RunpodDirect ${RUNPODDIRECT_SHA}" && \
    git remote add origin https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-Ollama
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Ollama ${COMFYUI_OLLAMA_SHA}" && \
    git remote add origin https://github.com/stavsap/comfyui-ollama.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-Impact-Pack
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ImpactPack ${IMPACT_PACK_SHA}" && \
    git remote add origin https://github.com/ltdrdata/ComfyUI-Impact-Pack.git

WORKDIR /tmp/build/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite
RUN git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "VHS ${VIDEOHELPERSUITE_SHA}" && \
    git remote add origin https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git

# ============================================================================
# STAGE 5: comfyui-deps - PyTorch + Python packages
# ============================================================================
FROM comfyui-core AS comfyui-deps

ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION
ARG TORCH_INDEX_SUFFIX=cu128
ARG HAS_NVIDIA_GPU=true

WORKDIR /tmp/build

# Install PyTorch
RUN if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
    echo "Installing PyTorch with CUDA..." && \
    python3.12 -m pip install --no-cache-dir \
    torch==${TORCH_VERSION} \
    torchvision==${TORCHVISION_VERSION} \
    torchaudio==${TORCHAUDIO_VERSION} \
    --index-url https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}; \
    else \
    echo "Installing PyTorch CPU..." && \
    python3.12 -m pip install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cpu; \
    fi

# Generate requirements.lock with hash verification
RUN cat ComfyUI/requirements.txt > requirements.in && \
    for node_dir in ComfyUI/custom_nodes/*/; do \
    node_name=$(basename "$node_dir"); \
    case "$node_name" in \
    ComfyUI-Impact-Pack|ComfyUI-VideoHelperSuite) continue ;; \
    esac; \
    if [ -f "$node_dir/requirements.txt" ]; then \
    sed -i 's/^dotenv$/python-dotenv/' "$node_dir/requirements.txt"; \
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
    echo "pillow>=12.1.1" >> constraints.txt

RUN pip install --no-cache-dir pip-tools && \
    PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
    python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# Install Impact Pack + VideoHelperSuite without hash verification
RUN for node in ComfyUI-Impact-Pack ComfyUI-VideoHelperSuite; do \
    if [ -f "ComfyUI/custom_nodes/$node/requirements.txt" ]; then \
    sed -i 's/^dotenv$/python-dotenv/' "ComfyUI/custom_nodes/$node/requirements.txt"; \
    python3.12 -m pip install --no-cache-dir -r "ComfyUI/custom_nodes/$node/requirements.txt" || true; \
    fi; \
    done

# Pre-populate ComfyUI-Manager cache
COPY scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI to final location
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# ============================================================================
# STAGE 6: dashy - Web portal
# ============================================================================
FROM lissy93/dashy:latest AS dashy

# ============================================================================
# STAGE 7: tools-binary - Ollama + FileBrowser + code-server
# ============================================================================
FROM base-system AS tools-binary

ARG FILEBROWSER_VERSION=v2.59.0
ARG FILEBROWSER_SHA256=8cd8c3baecb086028111b912f252a6e3169737fa764b5c510139e81f9da87799

# FileBrowser
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
    echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    rm /tmp/fb.tar.gz

# Ollama
ENV OLLAMA_VERSION=0.18.2
RUN curl -fSL --retry 5 --retry-delay 3 "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" -o /tmp/ollama.tar.zst && \
    mkdir -p /tmp/ollama_extract && \
    tar -I zstd -xf /tmp/ollama.tar.zst -C /tmp/ollama_extract && \
    find /tmp/ollama_extract -name "ollama" -type f -exec mv {} /usr/local/bin/ollama \; && \
    chmod +x /usr/local/bin/ollama && \
    rm -rf /tmp/ollama*

# code-server
RUN curl -fSL "https://github.com/coder/code-server/releases/download/v4.112.0/code-server-4.112.0-linux-amd64.tar.gz" -o /tmp/code-server.tar.gz && \
    tar xzf /tmp/code-server.tar.gz -C /tmp && \
    mv /tmp/code-server-4.112.0-linux-amd64/bin/code-server /usr/local/bin/ && \
    chmod +x /usr/local/bin/code-server && \
    rm -rf /tmp/code-server*

# ============================================================================
# STAGE 8: tools-nodejs - Node.js 22.x
# ============================================================================
FROM base-system AS tools-nodejs

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STAGE 9: tools-monitoring - nvitop, gpustat, litellm, etc.
# ============================================================================
FROM base-system AS tools-monitoring

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    curl \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python3.12 get-pip.py \
    && rm get-pip.py

RUN python3.12 -m pip install --no-cache-dir --break-system-packages \
    nvitop gpustat gpustat-web 'litellm[proxy]' huggingface_hub[cli] hf_transfer && \
    ln -sf /usr/local/bin/hf /usr/local/bin/huggingface-cli

ENV HF_HUB_ENABLE_HF_TRANSFER=1

# ============================================================================
# STAGE 10: webui-open - Open WebUI
# ============================================================================
FROM base-system AS webui-open

ARG OPEN_WEBUI_VERSION=0.8.10

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    unzip \
    zip \
    curl \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python3.12 get-pip.py \
    && rm get-pip.py

WORKDIR /tmp/webui
RUN python3.12 -m pip download --no-deps open-webui==${OPEN_WEBUI_VERSION}

RUN unzip open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl -d content && \
    python3.12 -c "import os; f='content/open_webui-${OPEN_WEBUI_VERSION}.dist-info/METADATA'; t=open(f).read(); t=t.replace('ddgs==9.11.2', 'ddgs>=9.11.3').replace('ddgs ==9.11.2', 'ddgs>=9.11.3').replace('ddgs (==9.11.2)', 'ddgs (>=9.11.3)'); open(f,'w').write(t)" && \
    cd content && zip -q -r ../open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl * && \
    cd .. && rm -rf content

RUN python3.12 -m pip install --no-cache-dir ./open_webui-${OPEN_WEBUI_VERSION}-py3-none-any.whl ddgs==9.11.3 starlette-compress && \
    rm -rf /tmp/webui

# ============================================================================
# STAGE 11: tools-extra - aria2, rclone, AriaNg, Jupyter extensions
# ============================================================================
FROM base-system AS tools-extra

# aria2 + rclone
RUN apt-get update && \
    apt-get install -y --no-install-recommends aria2 rclone unzip zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# AriaNg
RUN mkdir -p /opt/ariang && \
    curl -fSL "https://github.com/mayswind/AriaNg/releases/download/1.3.13/AriaNg-1.3.13-AllInOne.zip" -o /tmp/ariang.zip && \
    unzip /tmp/ariang.zip -d /opt/ariang && \
    rm /tmp/ariang.zip

# ============================================================================
# FINAL STAGE: runtime - Combines all stages
# ============================================================================
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV OLLAMA_MODELS=/workspace/ollama-models
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_BASE_URL=http://localhost:11434
ENV OLLAMA_KEEP_ALIVE=10m
ENV WEBUI_PORT=3000
ENV DATA_DIR=/workspace/open-webui/data
ENV ENABLE_OLLAMA_API=True
ENV OLLAMA_API_BASE_URL=http://localhost:11434/api
ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV HF_HUB_ENABLE_HF_TRANSFER=1

ARG HAS_NVIDIA_GPU=true
ARG CUDA_VERSION_DASH=12-8

# Install base system packages + CUDA (combined for proper order)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    openssh-client \
    openssh-server \
    ffmpeg && \
    if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
    echo "Installing CUDA runtime ${CUDA_VERSION_DASH}..." && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} && \
    rm cuda-keyring_1.1-1_all.deb; \
    fi && \
    rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

# Copy from builder stages
COPY --from=comfyui-deps /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=comfyui-deps /usr/local/bin /usr/local/bin
COPY --from=comfyui-deps /usr/local/share/jupyter /usr/local/share/jupyter
COPY --from=comfyui-deps /opt/comfyui-baked /opt/comfyui-baked

# Copy Dashy
COPY --from=dashy /app /opt/dashy

# Copy binary tools
COPY --from=tools-binary /usr/local/bin/filebrowser /usr/local/bin/filebrowser
COPY --from=tools-binary /usr/local/bin/ollama /usr/local/bin/ollama

# code-server
RUN curl -fSL "https://github.com/coder/code-server/releases/download/v4.112.0/code-server-4.112.0-linux-amd64.tar.gz" -o /tmp/code-server.tar.gz && \
    tar xzf /tmp/code-server.tar.gz -C /tmp && \
    mv /tmp/code-server-4.112.0-linux-amd64/bin/code-server /usr/local/bin/ && \
    chmod +x /usr/local/bin/code-server && \
    mkdir -p /root/.local/share/code-server && \
    rm -rf /tmp/code-server*

# Copy Node.js
COPY --from=tools-nodejs /usr/bin/node /usr/bin/node
COPY --from=tools-nodejs /usr/bin/npm /usr/bin/npm
COPY --from=tools-nodejs /usr/bin/npx /usr/bin/npx
COPY --from=tools-nodejs /usr/lib/node_modules /usr/lib/node_modules

# Copy monitoring tools
COPY --from=tools-monitoring /usr/local/lib/python3.12/dist-packages /usr/local/lib/python3.12/dist-packages
COPY --from=tools-monitoring /usr/local/bin/nvitop /usr/local/bin/nvitop
COPY --from=tools-monitoring /usr/local/bin/gpustat /usr/local/bin/gpustat
COPY --from=tools-monitoring /usr/local/bin/gpustat-web /usr/local/bin/gpustat-web
COPY --from=tools-monitoring /usr/local/bin/litellm /usr/local/bin/litellm
COPY --from=tools-monitoring /usr/local/bin/huggingface-cli /usr/local/bin/huggingface-cli
COPY --from=tools-monitoring /usr/local/bin/hf /usr/local/bin/hf

# Copy Open WebUI
COPY --from=webui-open /usr/local/lib/python3.12/dist-packages/open_webui /usr/local/lib/python3.12/dist-packages/open_webui
COPY --from=webui-open /usr/local/lib/python3.12/dist-packages/ddgs* /usr/local/lib/python3.12/dist-packages/
COPY --from=webui-open /usr/local/lib/python3.12/dist-packages/starlette* /usr/local/lib/python3.12/dist-packages/

# Copy extra tools
COPY --from=tools-extra /usr/bin/aria2c /usr/bin/aria2c
COPY --from=tools-extra /usr/bin/rclone /usr/bin/rclone
COPY --from=tools-extra /opt/ariang /opt/ariang

# Jupyter config
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
    echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
    > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# Remove uv
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# CUDA environment
RUN if [ "${HAS_NVIDIA_GPU}" = "true" ]; then \
    echo "export PATH=/usr/local/cuda/bin:\${PATH}" >> /etc/environment && \
    echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64" >> /etc/environment && \
    echo "alias gpu='nvitop'" >> /etc/bash.bashrc; \
    fi

# SSH config
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    rm -f /etc/ssh_host_*

# Workspace
RUN mkdir -p /workspace/runpod-slim
WORKDIR /workspace/runpod-slim

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost:8188 || exit 1

# Expose ports
EXPOSE 80 8188 22 8888 8080 11434 3000 8443 8081 6800 5572 4000 8000

# Copy start script
COPY start_v3.sh /start.sh

ENTRYPOINT ["/start.sh"]
