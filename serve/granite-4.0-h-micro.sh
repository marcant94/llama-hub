#!/usr/bin/env bash
# =============================================================================
# Granite 4.0 H Micro (MoE hibrido, 3B totales / 800M activos)
#
# Equivale a granite4:micro-h de Ollama.
# Modelo: granite-4.0-h-micro (Q4_K_M ~2 GB, hibrido Mamba+MoE, 800M activos)
#
# Draft externo descartado a proposito. Este modelo es hibrido (Mamba) y el
# draft externo es inviable: cada aceptacion parcial obliga a restaurar un
# checkpoint completo del estado recurrente (+ replay), y con drafts cortos y
# ~50% de aceptacion eso ocurre casi en cada paso. Ver granite-4.0-h-tiny.sh.
# El ngram-mod (por defecto, via SPEC_NGRAM) SI se mantiene: no propone nada en
# prosa y acepta drafts largos enteros en texto repetitivo, sin rollback
# parcial.
#
# Uso: ./serve/granite-4.0-h-micro.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Granite 4.0 H Micro (MoE)"

# Identidad del modelo (GGUF oficiales de IBM)
MODEL_ALIAS="granite-4-micro"
MODEL_REPO="ibm-granite/granite-4.0-h-micro-GGUF"

# Cuantizacion preferida
MODEL_QUANT="Q4_K_M"
MODEL_QUANT_FALLBACK="Q4_0"

# Modelo de texto sin mmproj
MODEL_MMPROJ_PATTERN=""

# ngram-mod (por defecto) se mantiene; aqui solo se descarta el draft externo.

# El contexto máximo se autodetecta de los metadatos GGUF (ver lib/common.sh).

# No usa PLE
PLE_MODEL=false

MODEL_ENV_EXTRA=()

llama_serve_model "$@"
