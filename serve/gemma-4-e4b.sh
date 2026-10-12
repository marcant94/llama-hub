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
# QAT (Quantization-Aware Training): re-entrenado con cuantización simulada,
# conserva calidad cercana a bf16 con ~5 GB. Incluye drafter MTP (~60 MB).
MODEL_ALIAS="gemma-4-e4b"
MODEL_REPO="unsloth/gemma-4-E4B-it-qat-GGUF"

# Cuantización preferida (patrón en el nombre del fichero)
MODEL_QUANT="UD-Q4_K_XL"

# Proyector multimodal (patrón del fichero mmproj dentro del repo)
MODEL_MMPROJ_PATTERN="mmproj.*\.gguf"

# Drafter MTP (speculative decoding del propio modelo; smart Q4_0 en la raíz
# del repo, lo encuentra -hf automáticamente; aquí lo descargamos nosotros).
# Sin anclar (^...$): find devuelve rutas completas y el ^ nunca casaría.
# El veto excluye la carpeta MTP/ del repo (otras precisiones del drafter);
# queremos el smart Q4_0 de la raíz.
MODEL_MTP_PATTERN="mtp-gemma.*\.gguf"
MODEL_MTP_VETO="^MTP/"
# Longitud del draft (recomendado 4 para el MTP de Gemma 4, segun Unsloth)
MODEL_SPEC_DRAFT_N_MAX=4

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
