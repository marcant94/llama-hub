#!/usr/bin/env bash
# =============================================================================
# Detecta el backend que se usaría con BACKEND=auto.
# Uso: ./bin/detect-backend.sh
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

llama_resolve_backend "${1:-auto}"
