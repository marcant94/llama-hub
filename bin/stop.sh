#!/usr/bin/env bash
# =============================================================================
# Para y elimina el contenedor llama-server.
# Uso: ./bin/stop.sh
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_cmd docker
info "parando llama-server..."
llama_compose_down
info "detenido."
