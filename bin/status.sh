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

# Puerto publicado en el host: se lo preguntamos a docker en vez de deducirlo de
# .env, porque compose publica ${PORT:-18080} mientras el contenedor siempre
# escucha en 8080 dentro. Así acierta aunque cambies el puerto.
port="$(docker port "$cid" 8080/tcp 2>/dev/null | head -n1 | sed 's/.*://' || true)"
[[ -n "$port" ]] || port="$PORT"

echo "--- contenedor ----------------------------------------------------------"
docker ps -a -f "id=$cid" --format 'estado:   {{.Status}}
imagen:   {{.Image}}
puertos:  {{.Ports}}'

echo
echo "--- servidor ------------------------------------------------------------"
if command -v curl >/dev/null 2>&1; then
    if curl -fsS "http://localhost:${port}/health" >/dev/null 2>&1; then
        info "health: OK (http://localhost:${port}/health)"
    else
        warn "health: sin respuesta en http://localhost:${port}/health"
    fi

    if props="$(curl -fsS "http://localhost:${port}/props" 2>/dev/null)"; then
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
