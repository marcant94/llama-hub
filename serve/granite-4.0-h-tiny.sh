#!/usr/bin/env bash
# =============================================================================
# Granite 4.0 H Tiny (MoE hibrido, 7B totales / 1B activo)
#
# Equivale a granite4:tiny-h (alias de granite4:7b-a1b-h) de Ollama.
# Modelo: granite-4.0-h-tiny (Q4_K_M = 3.94 GB, hibrido Mamba+MoE, 1B activo)
#
# Draft externo descartado a proposito. Este modelo es hibrido (Mamba) y el
# draft externo es inviable: cada aceptacion parcial obliga a restaurar un
# checkpoint completo del estado recurrente (+ replay), y con drafts cortos y
# ~50% de aceptacion eso ocurre casi en cada paso. Medido en RX 6650 XT
# (Vulkan): 15 t/s con draft-simple frente a ~45 t/s del target solo.
# El ngram-mod (por defecto, via SPEC_NGRAM) SI se mantiene: no propone nada en
# prosa y acepta drafts largos enteros en texto repetitivo, sin rollback
# parcial. Medido: 44.5 -> 44.5 t/s en prosa y 44.8 -> 121.8 t/s en repetitivo.
#
# Uso: ./serve/granite-4.0-h-tiny.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Granite 4.0 H Tiny (MoE)"

# Identidad del modelo (GGUF oficiales de IBM)
MODEL_ALIAS="granite-4-tiny"
MODEL_REPO="ibm-granite/granite-4.0-h-tiny-GGUF"

# Cuantizacion preferida
MODEL_QUANT="Q4_K_M"
MODEL_QUANT_FALLBACK="Q4_0"

# Modelo de texto sin mmproj
MODEL_MMPROJ_PATTERN=""

# ngram-mod (por defecto) se mantiene; aqui solo se descarta el draft externo.
# Para probarlo (no recomendado en hibridos), define el draft externo, p. ej.:
#   MODEL_DRAFT_REPO="ibm-granite/granite-4.0-h-1b-GGUF"
#   MODEL_DRAFT_QUANT="Q4_K_M"

# Contexto maximo del modelo (max_position_embeddings del config)
MODEL_CTX_MAX=131072

# No usa PLE
PLE_MODEL=false

MODEL_ENV_EXTRA=()

llama_serve_model "$@"
