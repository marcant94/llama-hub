#!/usr/bin/env bash
# =============================================================================
# Gemma 4 E4B — usa Per-Layer Embeddings (PLE) y es multimodal (visión/audio).
# Uso: ./serve/gemma-4-e4b.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Gemma 4 E4B"

# Identidad del modelo
MODEL_ALIAS="gemma-4-e4b"
MODEL_REPO="unsloth/gemma-4-E4B-it-GGUF"
MODEL_REPO_FALLBACK="bartowski/google_gemma-4-E4B-it-GGUF"

# Cuantización preferida (orden de intento: patrón en el nombre del fichero)
MODEL_QUANT="UD-Q4_K_XL"
MODEL_QUANT_FALLBACK="Q4_K_M"

# Proyector multimodal (patrón del fichero mmproj dentro del repo)
MODEL_MMPROJ_PATTERN="mmproj.*\.gguf"

# ¿El modelo usa tablas PLE que conviene desviar a RAM? (sí para E2B/E4B)
PLE_MODEL=true

# Flags propios del modelo (líneas LLAMA_ARG_* extra)
MODEL_ENV_EXTRA=(
    "LLAMA_ARG_TEMPERATURE=1.0"
    "LLAMA_ARG_TOP_K=64"
    "LLAMA_ARG_TOP_P=0.95"
)

llama_serve_model "$@"
