#!/bin/bash
set -e

# Configuración básica
PASSWORD="${PASSWORD:-admin123}"
COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv-cu128"
DB_FILE="/workspace/runpod-slim/filebrowser.db"

# Copy ComfyUI if not exists
mkdir -p "$COMFYUI_DIR"
if [ ! -f "$COMFYUI_DIR/main.py" ]; then
    cp -r /opt/comfyui-baked/. "$COMFYUI_DIR/"
fi

# 1. SSH
mkdir -p ~/.ssh
mkdir -p /var/run/sshd
ssh-keygen -A
ssh-keyscan -H localhost >> ~/.ssh/known_hosts 2>/dev/null || true
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys 2>/dev/null || true
chmod 600 ~/.ssh/authorized_keys
echo "root:${PASSWORD}" | chpasswd
/usr/sbin/sshd

# 2. FileBrowser
if [ ! -f "$DB_FILE" ]; then
    filebrowser config init -d "$DB_FILE"
    filebrowser config set --address 0.0.0.0 --port 8080 --root /workspace --baseurl /filebrowser --auth.method=json -d "$DB_FILE"
    filebrowser users add admin adminadmin12 --perm.admin -d "$DB_FILE"
fi
nohup filebrowser -d "$DB_FILE" --baseurl /filebrowser &> /filebrowser.log &

# 3. Ollama
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MODELS=/workspace/ollama-models
mkdir -p "$OLLAMA_MODELS"
nohup ollama serve &> /ollama.log &

# 4. Open WebUI
export WEBUI_SECRET_KEY="secret123"
mkdir -p /workspace/open-webui/data
export DATA_DIR=/workspace/open-webui/data
nohup open-webui serve --host 0.0.0.0 --port 3000 &> /openwebui.log &

# 5. Code-Server
mkdir -p /workspace/code-server
nohup code-server --auth none --bind-addr 0.0.0.0:8443 --user-data-dir /workspace/code-server /workspace &> /codeserver.log &

# 6. JupyterLab
mkdir -p /workspace
nohup jupyter lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 --NotebookApp.token='' &> /jupyter.log &

# 7. Aria2 RPC
mkdir -p /workspace/models
nohup aria2c --enable-rpc --rpc-listen-all --rpc-allow-origin-all --max-connection-per-server=16 --split=16 --min-split-size=1M --dir=/workspace/models &> /aria2.log &

# 8. AriaNg Web UI
cd /opt/ariang
nohup python3.12 -m http.server 8081 &> /ariang.log &

# 9. Rclone GUI
nohup rclone rcd --rc-web-gui --rc-addr :5572 --rc-user admin --rc-pass admin --rc-serve --rc-web-gui-no-open-browser &> /rclone.log &

# 10. GPU Monitor
nohup gpustat-web --port 4000 &> /gpu-monitor.log &

# 11. LiteLLM Proxy
nohup litellm --port 8000 --host 0.0.0.0 --telemetry False &> /litellm.log &



# Configurar Dashy
DASHY_DIR="/opt/dashy"
mkdir -p "$DASHY_DIR/user-data"
DASHY_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

cat << EOF > "$DASHY_DIR/user-data/conf.yml"
pageInfo:
  title: Portal AI
appConfig:
  theme: nord-frost
  language: es
  auth:
    users:
      - user: admin
        hash: $DASHY_HASH
        type: admin
  statusCheck: true
  statusCheckInterval: 60
sections:
  - name: ComfyUI
    items:
      - title: ComfyUI
        description: Generación de imágenes y video
        url: http://localhost:8188
        icon: hl-comfyui
        statusCheck: true
        statusCheckUrl: http://localhost:8188
  - name: Modelos
    items:
      - title: Open WebUI
        description: Chat con LLMs locales
        url: http://localhost:3000
        icon: hl-openai
        statusCheck: true
        statusCheckUrl: http://localhost:3000
      - title: Ollama
        description: Motor de LLMs
        url: http://localhost:11434
        icon: hl-ollama
        statusCheck: true
        statusCheckUrl: http://localhost:11434
      - title: LiteLLM
        description: API Gateway (OpenAI compatible)
        url: http://localhost:8000
        icon: hl-openai
        statusCheck: true
        statusCheckUrl: http://localhost:8000
  - name: Desarrollo
    items:
      - title: Code-Server
        description: VS Code en el navegador
        url: http://localhost:8443
        icon: hl-visual-studio-code
        statusCheck: true
        statusCheckUrl: http://localhost:8443
      - title: JupyterLab
        description: Notebooks interactivos
        url: http://localhost:8888
        icon: hl-jupyter
        statusCheck: true
        statusCheckUrl: http://localhost:8888
  - name: Archivos
    items:
      - title: FileBrowser
        description: Explorador de archivos
        url: http://localhost:8080
        icon: hl-filebrowser
        statusCheck: true
        statusCheckUrl: http://localhost:8080
      - title: AriaNg
        description: Gestor de descargas
        url: http://localhost:8081
        icon: fas fa-download
        statusCheck: true
        statusCheckUrl: http://localhost:8081
      - title: Rclone GUI
        description: "user: admin / pass: admin"
        url: http://localhost:5572
        icon: hl-rclone
        statusCheck: false
  - name: Monitor
    items:
      - title: GPU Monitor
        description: Métricas de GPU
        url: http://localhost:4000
        icon: hl-nvidia
        statusCheck: true
        statusCheckUrl: http://localhost:4000
EOF

# Iniciar Dashy
cd "$DASHY_DIR"
PORT=80 NODE_ENV=production nohup node server.js &> /dashy.log &
echo "Dashy iniciado"

# ComfyUI (Foreground)
cd "$COMFYUI_DIR"
if [ -d "$VENV_DIR" ]; then source "$VENV_DIR/bin/activate"; fi
EXTRA_ARGS=""
if ! python3.12 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    EXTRA_ARGS="--cpu"
fi
python3.12 main.py --listen 0.0.0.0 --port 8188 $EXTRA_ARGS
