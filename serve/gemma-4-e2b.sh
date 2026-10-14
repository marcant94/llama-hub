#!/usr/bin/env bash
# =============================================================================
# Gemma 4 E2B — usa Per-Layer Embeddings (PLE) y es multimodal (visión/audio).
# Uso: ./serve/gemma-4-e2b.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Gemma 4 E2B"

# Identidad del modelo
# QAT (Quantization-Aware Training): re-entrenado con cuantización simulada,
# conserva calidad cercana a bf16 con ~2.6 GB. El repo incluye un drafter MTP
# que aquí no usamos (ver nota del drafting más abajo).
MODEL_ALIAS="gemma-4-e2b"
MODEL_REPO="unsloth/gemma-4-E2B-it-qat-GGUF"

# Cuantización preferida (patrón en el nombre del fichero)
MODEL_QUANT="UD-Q4_K_XL"

# Proyector multimodal (patrón del fichero mmproj dentro del repo)
MODEL_MMPROJ_PATTERN="mmproj.*\.gguf"

# Drafting por n-gramas: se deja el valor por defecto de lib/common.sh
# (SPEC_NGRAM=true) sin forzarlo aquí, para que .env pueda desactivarlo.
# No garantiza la salida idéntica a sin draft, y el drafter MTP del propio
# modelo (mtp-gemma-*) no se usa: solo gana en código/repetitivo y pierde en
# prosa (ver gemma-4-e4b.sh para las cifras).

# ¿El modelo usa tablas PLE que conviene desviar a RAM? (sí para E2B/E4B)
PLE_MODEL=true

# Flags propios del modelo (líneas LLAMA_ARG_* extra).
# Los valores de muestreo son los *defaults del servidor* para toda petición
# que no especifique los suyos (el cliente puede sobrescribirlos por request).
MODEL_ENV_EXTRA=(
    "LLAMA_ARG_TEMPERATURE=1.0"
    "LLAMA_ARG_TOP_K=64"
    "LLAMA_ARG_TOP_P=0.95"
)

llama_serve_model "$@"
