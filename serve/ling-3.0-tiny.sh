#!/usr/bin/env bash
# =============================================================================
# Ling 3.0 tiny (8B, inclusionAI) — modelo de texto.
# Uso: ./serve/ling-3.0-tiny.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Ling 3.0 tiny"

# Identidad del modelo
MODEL_ALIAS="ling-3.0-tiny"
MODEL_REPO="inclusionAI/Ling-3.0-tiny-GGUF"
MODEL_REPO_FALLBACK="bartowski/Ling-3.0-tiny-GGUF"

# Cuantización preferida (orden de intento: patrón en el nombre del fichero)
MODEL_QUANT="Q4_K_M"
MODEL_QUANT_FALLBACK="Q5_K_M"

# Modelo de texto: sin proyector multimodal.
MODEL_MMPROJ_PATTERN=""

# No usa PLE.
PLE_MODEL=false

# Flags propios del modelo (líneas LLAMA_ARG_* extra).
# Aquí podrías fijar muestreo, p. ej. "LLAMA_ARG_TEMPERATURE=0.7"; serían los
# *defaults del servidor* (el cliente puede sobrescribirlos por petición).
MODEL_ENV_EXTRA=()

llama_serve_model "$@"
