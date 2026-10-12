#!/usr/bin/env bash
# =============================================================================
# Granite 4.0 H Tiny (MoE hibrido, 7B totales / 1B activo) + drafter 1b
#
# Equivale a granite4:tiny-h (alias de granite4:7b-a1b-h) de Ollama.
# Target: granite-4.0-h-tiny (Q4_K_M = 3.94 GB, hibrido Mamba+MoE, 1B activo)
# Draft:  granite-4.0-h-1b    (Q4_K_M = 0.84 GB, mismo tokenizer, granite4:1b)
#   -ngld configurable (MODEL_SPEC_DRAFT_NGL). Sin medir, sin promesas: la
#   ganancia depende de la tasa de aceptacion; medir con los logs del server.
#
# Uso: ./serve/granite-4.0-h-tiny-draft.sh [backend]
#   backend: auto (def.) | cpu | nvidia | amd-vulkan | amd-rocm
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_NAME="Granite 4.0 H Tiny (MoE) + draft 1b"

# Identidad del modelo (GGUF oficiales de IBM)
MODEL_ALIAS="granite-4-tiny"
MODEL_REPO="ibm-granite/granite-4.0-h-tiny-GGUF"

# Cuantizacion preferida
MODEL_QUANT="Q4_K_M"
MODEL_QUANT_FALLBACK="Q4_0"

# Modelo de texto sin mmproj
MODEL_MMPROJ_PATTERN=""

# Draft externo: granite-4.0-h-1b (misma familia/tokenizer que el target)
MODEL_DRAFT_REPO="ibm-granite/granite-4.0-h-1b-GGUF"
MODEL_DRAFT_QUANT="Q4_K_M"

# Longitud del draft y capas del draft en GPU: vacio = auto, 0 = draft en CPU.
MODEL_SPEC_DRAFT_N_MAX=3
MODEL_SPEC_DRAFT_NGL=""

# Contexto maximo del modelo (max_position_embeddings del config)
MODEL_CTX_MAX=131072

# No usa PLE
PLE_MODEL=false

MODEL_ENV_EXTRA=()

llama_serve_model "$@"
