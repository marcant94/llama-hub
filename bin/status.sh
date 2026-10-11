#!/usr/bin/env bash
# =============================================================================
# Muestra el estado del contenedor y del servidor (health + modelo cargado).
# Uso: ./bin/status.sh [-f]     (-f = sigue los logs en vivo)
# =============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_cmd docker

cid="$(docker ps -aq -f 'name=^llama-server$' || true)"
if [[ -z "$cid" ]]; then
    warn "no hay contenedor 'llama-server' (¿has arrancado algún modelo?)"
    exit 0
fi

echo "--- contenedor ----------------------------------------------------------"
docker ps -a -f "id=$cid" --format 'estado:   {{.Status}}
imagen:   {{.Image}}
puertos:  {{.Ports}}'

echo
echo "--- servidor ------------------------------------------------------------"
if command -v curl >/dev/null 2>&1; then
    if curl -fsS "http://localhost:${PORT}/health" >/dev/null 2>&1; then
        info "health: OK (http://localhost:${PORT}/health)"
    else
        warn "health: sin respuesta en http://localhost:${PORT}/health"
    fi

    if props="$(curl -fsS "http://localhost:${PORT}/props" 2>/dev/null)"; then
        model_path="$(printf '%s' "$props" | grep -o '"model_path":"[^"]*"' | head -n1 | sed 's/.*:"//; s/"$//')"
        n_ctx="$(printf '%s' "$props" | grep -o '"n_ctx":[0-9]*' | head -n1 | sed 's/.*://')"
        [[ -n "$model_path" ]] && info "modelo: $model_path"
        [[ -n "$n_ctx" ]] && info "contexto: $n_ctx tokens"
    fi
else
    warn "curl no disponible; omito la comprobación de health"
fi

if [[ "${1:-}" == "-f" ]]; then
    echo
    info "siguiendo logs (Ctrl+C para salir)..."
    (cd "$LLAMA_HUB_ROOT" && llama_compose -f docker-compose.yml logs -f --tail=50)
fi
