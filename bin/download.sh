#!/usr/bin/env bash
# =============================================================================
# Descarga un fichero .gguf de HuggingFace a la carpeta de modelos.
# Uso: ./bin/download.sh <repo> <patrón> [veto]
#   <repo>    p. ej. unsloth/gemma-4-E4B-it-GGUF
#   <patrón>  regex que debe aparecer en el nombre (p. ej. Q4_K_XL o mmproj)
#   [veto]    regex que excluye coincidencias (p. ej. mmproj)
# Ejemplos:
#   ./bin/download.sh unsloth/gemma-4-E4B-it-GGUF UD-Q4_K_XL mmproj
#   ./bin/download.sh unsloth/gemma-4-E4B-it-GGUF mmproj
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

if [[ $# -lt 2 ]]; then
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

need_cmd curl
repo="$1"
pat="$2"
veto="${3:-}"

path="$(llama_ensure_file "$repo" ".*${pat}.*\.gguf" "$veto")" \
    || die "no se encontró en '$repo' ningún fichero que case con /$pat/i"

info "disponible en: $path"
