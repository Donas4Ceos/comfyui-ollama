# RunPod Setup Guide

## 1. Modelos recomendados — RTX Pro 6000 (96 GB VRAM)

Con 96 GB puedes correr los modelos más grandes sin quantización agresiva.

### LLMs (similares a un modelo frontier)

| Modelo | VRAM aprox. | Notas |
|--------|------------|-------|
| **DeepSeek-R1 671B (Q4)** | ~90 GB | El más cercano a frontier, razonamiento excepcional |
| **Llama 4 Maverick 400B (MoE Q4)** | ~70 GB | Meta, muy capaz para coding y chat |
| **Qwen3 235B (MoE Q4)** | ~60 GB | Excelente para código, multilingüe |

### Modelos de video (ComfyUI)

| Modelo | VRAM | Notas |
|--------|------|-------|
| **Wan 2.1 14B** | ~20 GB | Texto → Video, mejor open source actualmente |
| **HunyuanVideo** | ~24 GB | Alta calidad |

> Con 96 GB puedes tener un LLM 70B + modelo de video corriendo simultáneamente.

### Descargar modelos via Ollama (en el Pod)

```bash
# Via terminal en JupyterLab o SSH
ollama pull deepseek-r1:70b
ollama pull qwen3:72b
```

Los modelos se guardan en `/workspace/ollama-models` (volumen persistente en RunPod).

### Descargar modelos de ComfyUI (checkpoints, LoRAs, etc.)

Usa FileBrowser (`:8080`) o JupyterLab (`:8888`) para subir/bajar archivos a:
- `/workspace/runpod-slim/ComfyUI/models/checkpoints`
- `/workspace/runpod-slim/ComfyUI/models/loras`

---

## 2. MCP para controlar RunPod

RunPod tiene un servidor MCP oficial que permite gestionar Pods, templates y volúmenes desde tu editor local (Cursor, VS Code, Claude, etc.).

**Repositorio:** [github.com/runpod/runpod-mcp](https://github.com/runpod/runpod-mcp)

### Configuración rápida

1. Obtén tu API key en RunPod → Settings → API Keys
2. En tu editor (ej. Cursor, `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "runpod": {
      "command": "npx",
      "args": ["-y", "@runpod/mcp"],
      "env": {
        "RUNPOD_API_KEY": "tu-api-key-aqui"
      }
    }
  }
}
```

3. Ahora puedes decirle a tu asistente cosas como:
   - *"Crea un Pod con esta imagen y 1x A100"*
   - *"Para el Pod que está corriendo"*
   - *"Lista mis templates"*

---

## 3. Publicar la imagen en Docker Hub

```bash
# 1. Login
docker login

# 2. Build y push en un solo comando (usa docker-bake.hcl)
docker buildx bake regular --push

# La imagen queda disponible como:
# docker.io/tzicuri/comfyui-ollama:latest
# docker.io/tzicuri/comfyui-ollama:slim-cuda12.8
```

En RunPod al crear el Template:
- **Container Image:** `tzicuri/comfyui-ollama:latest`
- **Expose Ports:** `8188, 8080, 8888, 11434, 3000, 8443, 8081, 5572, 4000`
- **Volume Mount:** `/workspace` (mínimo 50 GB recomendado)

---

## 4. ¿Hay que subir los 17 GB siempre?

**No.** Docker usa capas (layers). La primera vez sube todo (~17 GB), pero en builds futuros **solo suben las capas modificadas**.

Ejemplo: si sólo cambias `start.sh`, la siguiente subida es de ~40 KB.

### Alternativa: CI/CD en GitHub Actions

El repositorio ya tiene `.github/`. Puedes configurar un workflow que haga el build y push directamente desde los servidores de GitHub, sin consumir tu ancho de banda local.

---

## 5. Usar modelos del Pod en OpenCode

Una vez que el Pod esté corriendo, expone Ollama en una URL pública:

```
https://<pod-id>-11434.proxy.runpod.net
```

En OpenCode (o cualquier cliente compatible con OpenAI API):

```bash
# .env o configuración del cliente
OPENAI_BASE_URL=https://<pod-id>-11434.proxy.runpod.net/v1
OPENAI_API_KEY=ollama   # cualquier string, Ollama no verifica
MODEL=deepseek-r1:70b
```

> Puedes mantener el Pod encendido permanentemente o automatizar el encendido/apagado con el **MCP de RunPod** desde tu editor.

---

## Puertos del contenedor

| Puerto | Servicio | Credenciales |
|--------|----------|-------------|
| `8188` | ComfyUI | — |
| `8080` | FileBrowser | `admin` / `adminadmin12` |
| `8888` | JupyterLab | Token via `JUPYTER_PASSWORD` |
| `11434` | Ollama API | — |
| `3000` | Open WebUI | `admin@openwebui.com` / `WEBUI_SECRET_KEY` |
| `8443` | Code-Server | Password via logs (`CODE_SERVER_PASSWORD`) |
| `8081` | AriaNg (Downloads) | — (Gestiona aria2 en :6800) |
| `5572` | Rclone GUI | `admin` / `adminadmin12` |
| `4000` | GPU Monitor (Web) | — (Visualización en tiempo real) |
| `22` | SSH | Ver logs para password generado |
