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
# conserva calidad cercana a bf16 con ~5 GB. El repo incluye un drafter MTP que
# aquí no usamos (ver nota del drafting más abajo).
MODEL_ALIAS="gemma-4-e4b"
MODEL_REPO="unsloth/gemma-4-E4B-it-qat-GGUF"

# Cuantización preferida (patrón en el nombre del fichero)
MODEL_QUANT="UD-Q4_K_XL"

# Proyector multimodal (patrón del fichero mmproj dentro del repo)
MODEL_MMPROJ_PATTERN="mmproj.*\.gguf"

# Drafting por n-gramas: se deja el valor por defecto de lib/common.sh
# (SPEC_NGRAM=true) sin forzarlo aquí, para que .env pueda desactivarlo.
# Medido en RX 6650 XT (Vulkan, máquina libre): 52 -> 56 t/s en prosa y
# 52 -> 130 t/s en texto repetitivo; nunca más lento.
# OJO: el drafting especulativo NO garantiza la salida idéntica a sin draft
# (verificado por md5; diverge de forma reproducible).
# Se probó también el drafter MTP del propio modelo (mtp-gemma-*): solo gana en
# código (56 t/s) y repetitivo (93 t/s), y pierde en prosa (40 vs 52).

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
