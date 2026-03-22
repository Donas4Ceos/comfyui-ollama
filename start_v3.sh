#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv-cu128"
OLD_VENV_DIR="$COMFYUI_DIR/.venv"
FILEBROWSER_CONFIG="/root/.config/filebrowser/config.json"
DB_FILE="/workspace/runpod-slim/filebrowser.db"

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                  #
# ---------------------------------------------------------------------------- #

# Setup SSH with optional key or random password
setup_ssh() {
    mkdir -p ~/.ssh
    
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A -q
    fi

    # If PUBLIC_KEY is provided, use it
    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        # Generate random password if no public key
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    # Configure SSH to preserve environment variables
    echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

    # Start SSH service
    /usr/sbin/sshd
}

# Export environment variables
export_env_vars() {
    echo "Exporting environment variables..."
    
    # Create environment files
    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"
    
    # Backup original files
    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true
    
    # Clear files
    > "$ENV_FILE"
    > "$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    > "$SSH_ENV_DIR"
    
    # Export to multiple locations for maximum compatibility
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH' | while read -r line; do
        # Get variable name and value
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)
        
        # Add to /etc/environment (system-wide)
        echo "$name=\"$value\"" >> "$ENV_FILE"
        
        # Add to PAM environment
        echo "$name DEFAULT=\"$value\"" >> "$PAM_ENV_FILE"
        
        # Add to SSH environment file
        echo "$name=\"$value\"" >> "$SSH_ENV_DIR"
        
        # Add to current shell
        echo "export $name=\"$value\"" >> /etc/rp_environment
    done
    
    # Add sourcing to shell startup files
    echo 'source /etc/rp_environment' >> ~/.bashrc
    echo 'source /etc/rp_environment' >> /etc/bash.bashrc
    
    # Set permissions
    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# Start Jupyter Lab server for remote access
start_jupyter() {
    mkdir -p /workspace
    echo "Starting Jupyter Lab on port 8888..."
    nohup jupyter lab \
        --allow-root \
        --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --FileContentsManager.preferred_dir=/workspace \
        --ServerApp.root_dir=/workspace \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin=* &> /jupyter.log &
    echo "Jupyter Lab started"
}

# Start Ollama server for serving LLMs
start_ollama() {
    mkdir -p /workspace/ollama-models
    echo "Starting Ollama on port 11434..."
    echo "Models will be stored in: $OLLAMA_MODELS"
    nohup ollama serve &> /ollama.log &
    echo "Ollama started"
}

# Start Open WebUI for Ollama
start_openwebui() {
    mkdir -p /workspace/open-webui/data
    
    if [ -z "$WEBUI_SECRET_KEY" ]; then
        export WEBUI_SECRET_KEY=$(openssl rand -base64 24)
        echo "Generated WEBUI_SECRET_KEY: $WEBUI_SECRET_KEY"
    fi
    
    export ACTUAL_WEBUI_PORT=${WEBUI_PORT:-3000}
    echo "Starting Open WebUI on port $ACTUAL_WEBUI_PORT..."
    echo "Access at: http://localhost:$ACTUAL_WEBUI_PORT"
    cd /workspace/open-webui
    if command -v open-webui >/dev/null 2>&1; then
        nohup open-webui serve --host 0.0.0.0 --port $ACTUAL_WEBUI_PORT &> /openwebui.log &
    else
        nohup python3.12 -m open_webui serve --host 0.0.0.0 --port $ACTUAL_WEBUI_PORT &> /openwebui.log &
    fi
    echo "Open WebUI started"
}

# Start Code-Server
    # Use the global PASSWORD if provided, else keep existing or generate random
    CODE_SERVER_PASSWORD="${PASSWORD:-${CODE_SERVER_PASSWORD:-}}"
    if [ -z "$CODE_SERVER_PASSWORD" ]; then
        export CODE_SERVER_PASSWORD=$(openssl rand -base64 12)
    fi
    echo "Starting Code-Server on port 8443..."
    echo "Access at: http://localhost:8443"
    echo "Password: $CODE_SERVER_PASSWORD"
    mkdir -p /workspace/code-server
    export PASSWORD=$CODE_SERVER_PASSWORD
    nohup code-server --bind-addr 0.0.0.0:8443 --user-data-dir /workspace/code-server --config /workspace/code-server/config.yaml /workspace &> /codeserver.log &
    echo "Code-Server started"
}

# Start Aria2 with RPC and AriaNg Web UI
start_aria2() {
    echo "Starting Aria2 RPC on port 6800..."
    # Ensure a centralized models folder exists in workspace
    # Defaulting to checkpoints for main downloads
    mkdir -p /workspace/models/checkpoints
    mkdir -p /workspace/models/loras
    mkdir -p /workspace/models/vae
    mkdir -p /workspace/models/controlnet
    
    # --rpc-listen-all is needed for RunPod proxying
    nohup aria2c --enable-rpc --rpc-listen-all --rpc-allow-origin-all --max-connection-per-server=16 --split=16 --min-split-size=1M --dir=/workspace/models/checkpoints --daemon &> /aria2.log &
    
    echo "Starting AriaNg Web UI on port 8081..."
    cd /opt/ariang
    nohup python3.12 -m http.server 8081 &> /ariang.log &
    echo "AriaNg started"
}

# Start Rclone Web GUI
start_rclone_gui() {
    echo "Starting Rclone Web GUI on port 5572..."
    # Default credentials same as FileBrowser for simplicity
    nohup rclone rcd --rc-web-gui --rc-addr :5572 --rc-user admin --rc-pass adminadmin12 --rc-serve --rc-web-gui-no-open-browser &> /rclone-gui.log &
    echo "Rclone Web GUI started"
}

# Start GPU Web Monitor (gpustat-web)
start_gpu_monitor() {
    echo "Starting GPU Web Monitor on port 4000..."
    
    # gpustat-web uses SSH to localhost, so we need to trust it
    mkdir -p ~/.ssh
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
    fi
    ssh-keyscan -H localhost >> ~/.ssh/known_hosts 2>/dev/null
    
    nohup gpustat-web --port 4000 &> /gpu-monitor.log &
    echo "GPU Web Monitor started"
}

# Start LiteLLM Proxy (Unified AI Gateway)
start_litellm() {
    echo "Starting LiteLLM Proxy on port 8000..."
    
    LITE_CONFIG="/workspace/runpod-slim/lite-config.yaml"
    if [ ! -f "$LITE_CONFIG" ]; then
        echo "Creating default LiteLLM config..."
        cat <<EOF > "$LITE_CONFIG"
model_list:
  - model_name: ollama-models
    litellm_params:
      model: ollama_chat/all
      api_base: http://localhost:11434
EOF
    fi
    
    # Start LiteLLM proxy
    nohup litellm --config "$LITE_CONFIG" --port 8000 --host 0.0.0.0 --telemetry False &> /litellm.log &
    echo "LiteLLM Proxy started"
}

# Start Dashy — Unified AI Orchestrator Portal
start_dashboard() {
    echo "Starting Dashy Portal on port 80..."
    DASHY_DIR="/opt/dashy"
    DASHY_CONF="$DASHY_DIR/user-data/conf.yml"
    mkdir -p "$DASHY_DIR/user-data"

    # Detect RunPod proxy base URL (e.g. https://<pod-id>-80.proxy.runpod.net)
    # We'll bake the pod prefix into the config if RUNPOD_POD_ID is set
    if [ -n "$RUNPOD_POD_ID" ]; then
        BASE="https://${RUNPOD_POD_ID}"
        _url() { echo "${BASE}-${1}.proxy.runpod.net"; }
    else
        _url() { echo "http://localhost:${1}"; }
    fi

    # Generate SHA-256 hash for Dashy auth (User: admin)
    DASHY_PASS="${PASSWORD:-password123}"
    DASHY_HASH=$(echo -n "$DASHY_PASS" | sha256sum | awk '{print $1}')

    cat << EOF > "$DASHY_CONF"
pageInfo:
  title: AI Orchestrator Portal
  description: Todos los servicios de tu instancia RunPod
  navLinks:
    - title: GitHub
      path: https://github.com/tzicuri/comfyui-ollama

appConfig:
  theme: nord-frost
  layout: auto
  iconSize: medium
  language: es
  auth:
    users:
      - user: admin
        hash: $DASHY_HASH
        type: admin
  statusCheck: true
  statusCheckInterval: 60
  startingView: default
  defaultOpeningMethod: newtab

sections:
  - name: 🎨 Generación Visual
    icon: fas fa-paint-brush
    items:
      - title: ComfyUI
        description: Generación de imágenes y video por nodos
        url: $(_url 8188)
        icon: fas fa-palette
        statusCheck: true
        statusCheckUrl: $(_url 8188)

  - name: 🤖 Modelos de Lenguaje (LLMs)
    icon: fas fa-brain
    items:
      - title: Open WebUI
        description: Interfaz de Chat Inteligente (Local)
        url: $(_url 3000)
        icon: fas fa-robot
        statusCheck: true
      - title: LiteLLM Proxy
        description: API Gateway compatible con OpenAI
        url: $(_url 8000)
        icon: fas fa-route
        statusCheck: true
      - title: Ollama API
        description: Motor interno de LLMs (sin interfaz)
        url: $(_url 11434)
        icon: fas fa-server
        statusCheck: true

  - name: 💻 Desarrollo y Código
    icon: fas fa-code
    items:
      - title: Code-Server
        description: VS Code en el navegador
        url: $(_url 8443)
        icon: fas fa-terminal
        statusCheck: true
      - title: JupyterLab
        description: Notebooks interactivos y terminal
        url: $(_url 8888)
        icon: fas fa-file-code
        statusCheck: true

  - name: 📁 Gestión de Archivos y Descargas
    icon: fas fa-folder-open
    items:
      - title: FileBrowser
        description: Explorador de /workspace (admin/adminadmin12)
        url: $(_url 8080)
        icon: fas fa-folder-open
        statusCheck: true
      - title: AriaNg
        description: Gestor de descargas aceleradas
        url: $(_url 8081)
        icon: fas fa-download
        statusCheck: true
      - title: Rclone GUI
        description: Sincronización con la nube (admin/adminadmin12)
        url: $(_url 5572)
        icon: fas fa-cloud-upload-alt
        statusCheck: true

  - name: 📊 Monitorización
    icon: fas fa-chart-line
    items:
      - title: GPU Monitor
        description: Métricas en vivo de VRAM y GPU
        url: $(_url 4000)
        icon: fas fa-microchip
        statusCheck: true
EOF

    # Start Dashy's built-in Node.js server
    cd "$DASHY_DIR"
    PORT=80 NODE_ENV=production nohup node server.js &> /dashy.log &
    echo "Dashy Portal started on port 80"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars

# First time setup: Copy baked ComfyUI to workspace if missing
mkdir -p "$COMFYUI_DIR"
if [ ! -f "$COMFYUI_DIR/main.py" ]; then
    echo "First time setup: Copying baked ComfyUI to workspace..."
    cp -r /opt/comfyui-baked/. "$COMFYUI_DIR/"
    echo "ComfyUI copied to workspace"
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Setting up venv..."
    cd "$COMFYUI_DIR"
    python3.12 -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    python -m ensurepip
else
    source "$VENV_DIR/bin/activate"
    echo "Using existing ComfyUI installation"
fi

# Initialize FileBrowser if not already done
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing FileBrowser..."
    filebrowser config init
    filebrowser config set --address 0.0.0.0
    filebrowser config set --port 8080
    filebrowser config set --root /workspace
    filebrowser config set --auth.method=json
    filebrowser users add admin adminadmin12 --perm.admin
else
    echo "Using existing FileBrowser configuration..."
fi

# Start FileBrowser
echo "Starting FileBrowser on port 8080..."
nohup filebrowser &> /filebrowser.log &

start_jupyter
start_ollama
start_openwebui
start_codeserver
start_aria2
start_rclone_gui
start_gpu_monitor
start_litellm
start_dashboard

# Create extra_model_paths.yaml to point to centralized /workspace/models
EXTRA_PATHS="/workspace/runpod-slim/ComfyUI/extra_model_paths.yaml"
if [ ! -f "$EXTRA_PATHS" ]; then
    echo "Creating extra_model_paths.yaml..."
    cat <<EOF > "$EXTRA_PATHS"
runpod:
    base_path: /workspace/models
    checkpoints: checkpoints
    clip: clip
    clip_vision: clip_vision
    configs: configs
    controlnet: controlnet
    embeddings: embeddings
    loras: loras
    upscale_models: upscale_models
    vae: vae
EOF
fi

# Create default comfyui_args.txt if it doesn't exist
ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" > "$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

# Migrate old CUDA 12.4 venv to cu128
if [ -d "$OLD_VENV_DIR" ] && [ ! -d "$VENV_DIR" ]; then
    NODE_COUNT=$(find "$COMFYUI_DIR/custom_nodes" -maxdepth 2 -name "requirements.txt" 2>/dev/null | wc -l)
    echo "============================================="
    echo "  CUDA 12.4 -> 12.8 migration"
    echo "  Reinstalling deps for $NODE_COUNT custom nodes"
    echo "  This may take several minutes"
    echo "============================================="
    mv "$OLD_VENV_DIR" "${OLD_VENV_DIR}.bak"
    cd "$COMFYUI_DIR"
    python3.12 -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    python -m ensurepip
    # Skip nodes baked into the image — their deps are in system site-packages
    BAKED_NODES="ComfyUI-Manager ComfyUI-KJNodes Civicomfy ComfyUI-RunpodDirect"
    CURRENT=0
    INSTALLED=0
    for req in "$COMFYUI_DIR"/custom_nodes/*/requirements.txt; do
        if [ -f "$req" ]; then
            NODE_NAME=$(basename "$(dirname "$req")")
            case " $BAKED_NODES " in
                *" $NODE_NAME "*) continue ;;
            esac
            CURRENT=$((CURRENT + 1))
            echo "[$CURRENT] $NODE_NAME"
            pip install -r "$req" 2>&1 | grep -E "^(Successfully|ERROR)" || true
            INSTALLED=$((INSTALLED + 1))
        fi
    done
    echo "Upgrading ComfyUI requirements..."
    pip install --upgrade -r "$COMFYUI_DIR/requirements.txt" 2>&1 | grep -E "^(Successfully|ERROR)" || true
    echo "Migration complete — $INSTALLED user nodes processed (${NODE_COUNT} total, baked nodes skipped)"
    echo "Old venv backed up at ${OLD_VENV_DIR}.bak — delete it to free space:"
    echo "  rm -rf ${OLD_VENV_DIR}.bak"
fi

# Warm up pip so ComfyUI-Manager's 5s timeout check doesn't fail on cold start
python -m pip --version > /dev/null 2>&1

# Start ComfyUI — keep container alive if it crashes so SSH/Jupyter remain accessible
cd $COMFYUI_DIR
FIXED_ARGS="--listen 0.0.0.0 --port 8188"

# Auto-detect GPU: if no real CUDA device is available at runtime, fall back to CPU mode
if ! python3.12 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    echo "No CUDA device available — starting ComfyUI in CPU mode"
    FIXED_ARGS="$FIXED_ARGS --cpu"
fi

# Read custom args (strip non-printable/binary chars from file for Windows compatibility)
if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(strings "$ARGS_FILE" | grep -v '^#' | tr '\n' ' ')
    if [ ! -z "$CUSTOM_ARGS" ]; then
        FIXED_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
    fi
fi

echo "Starting ComfyUI with args: $FIXED_ARGS"
python main.py $FIXED_ARGS &
COMFY_PID=$!
trap "kill $COMFY_PID 2>/dev/null" SIGTERM SIGINT
wait $COMFY_PID || true

echo "============================================="
echo "  ComfyUI crashed — check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $COMFYUI_DIR && source .venv-cu128/bin/activate"
echo "    python main.py $FIXED_ARGS"
echo "============================================="

sleep infinity
