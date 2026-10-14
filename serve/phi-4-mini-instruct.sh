#!/usr/bin/env bash
# =============================================================================
# Phi-4-mini-instruct (3.8B, Microsoft) — modelo de texto, instruct y multilingüe.
#
# Equivale a phi4-mini de Ollama (3.8B, Q4_K_M ~2.5 GB).
# Uso: ./serve/phi-4-mini-instruct.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Phi-4-mini-instruct"

# Identidad del modelo (GGUF de Unsloth, con el EOS corregido a <|end|>)
MODEL_ALIAS="phi-4-mini-instruct"
MODEL_REPO="unsloth/Phi-4-mini-instruct-GGUF"

# Cuantización preferida (patrón en el nombre del fichero)
MODEL_QUANT="Q4_K_M"
MODEL_QUANT_FALLBACK="Q5_K_M"

# Modelo de texto: sin proyector multimodal.
MODEL_MMPROJ_PATTERN=""

# No usa PLE.
PLE_MODEL=false

# Muestreo recomendado por Microsoft para Phi-4-mini-instruct: su model card usa
# do_sample=False (greedy), o sea temperatura 0 (determinista, "poco creativo").
# Son los *defaults del servidor*: el cliente puede sobrescribirlos por petición.
# Súbelo (p. ej. 0.7) si lo prefieres más variado.
MODEL_ENV_EXTRA=(
    "LLAMA_ARG_TEMPERATURE=0.0"
)

llama_serve_model "$@"
