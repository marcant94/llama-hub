#!/usr/bin/env bash
# =============================================================================
# Lista los modelos .gguf descargados en MODELS_DIR.
# Uso: ./bin/list-models.sh
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

mapfile -t files < <(find "$MODELS_DIR" -type f -iname '*.gguf' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
    info "no hay modelos descargados en $MODELS_DIR"
    exit 0
fi

printf '%-60s %10s\n' "FICHERO" "TAMAÑO"
printf '%-60s %10s\n' "-------" "------"
for f in "${files[@]}"; do
    printf '%-60s %10s\n' "${f#"$MODELS_DIR"/}" "$(du -h "$f" | cut -f1)"
done
