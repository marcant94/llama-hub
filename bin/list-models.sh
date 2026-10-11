#!/usr/bin/env bash
# =============================================================================
# Lista los modelos .gguf descargados en MODELS_DIR.
# Uso: ./bin/list-models.sh
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

shopt -s nullglob
files=("$MODELS_DIR"/*.gguf)

if [[ ${#files[@]} -eq 0 ]]; then
    info "no hay modelos descargados en $MODELS_DIR"
    exit 0
fi

printf '%-58s %10s\n' "FICHERO" "TAMAÑO"
printf '%-58s %10s\n' "-------" "------"
for f in "${files[@]}"; do
    printf '%-58s %10s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done
