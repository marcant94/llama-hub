#!/usr/bin/env bash
# =============================================================================
# llama-hub — utilidades compartidas
# Se hace `source` desde serve/*.sh y bin/*.sh. No ejecutar directamente.
# =============================================================================
set -euo pipefail

LLAMA_HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=./backend.sh
source "$LLAMA_HUB_ROOT/lib/backend.sh"

# -----------------------------------------------------------------------------
# Configuración: .env + valores por defecto
# -----------------------------------------------------------------------------
if [[ -f "$LLAMA_HUB_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$LLAMA_HUB_ROOT/.env"
    set +a
else
    printf '[llama-hub] aviso: no existe .env (copia .env.example a .env). Uso valores por defecto.\n' >&2
fi

: "${BACKEND:=auto}"
: "${MODELS_DIR:=$LLAMA_HUB_ROOT/models}"
: "${LLAMA_HOST:=0.0.0.0}"
: "${PORT:=8080}"
: "${LLAMA_SUFFIX:=}"
: "${API_KEY:=}"
: "${MEM_LIMIT:=0}"
: "${CPUS:=0}"
: "${RESTART_POLICY:=no}"
: "${HF_TOKEN:=}"
: "${PLE_TO_RAM:=true}"
: "${MMPROJ_TO_RAM:=true}"
: "${N_GPU_LAYERS:=all}"
: "${CTX_SIZE:=32768}"
: "${CACHE_TYPE_K:=q8_0}"
: "${CACHE_TYPE_V:=q8_0}"
: "${FLASH_ATTN:=on}"
: "${LAZY_MODE:=off}"
: "${CPU_MOE:=false}"
: "${N_CPU_MOE:=0}"
: "${MOE_CACHE_MIB:=0}"
: "${NVIDIA_VISIBLE_DEVICES:=all}"
: "${AMD_RENDER_NODE:=/dev/dri}"

# MODELS_DIR admite rutas relativas al repo, absolutas o con ~ al inicio.
MODELS_DIR="${MODELS_DIR/#\~/$HOME}"
case "$MODELS_DIR" in
    /*) : ;;
    *) MODELS_DIR="$LLAMA_HUB_ROOT/${MODELS_DIR#./}" ;;
esac
# Exportar la ruta resuelta para que docker compose la use en el bind mount
# (el entorno del shell tiene prioridad sobre .env; así ~ también se respeta).
export MODELS_DIR

RUN_DIR="$LLAMA_HUB_ROOT/.run"
MODEL_ENV_FILE="$RUN_DIR/model.env"

# -----------------------------------------------------------------------------
# Log y utilidades
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    _C_RST=$'\033[0m'; _C_INF=$'\033[36m'; _C_WRN=$'\033[33m'; _C_ERR=$'\033[31m'
else
    _C_RST=''; _C_INF=''; _C_WRN=''; _C_ERR=''
fi
info() { printf '%s[llama-hub]%s %s\n' "$_C_INF" "$_C_RST" "$*"; }
warn() { printf '%s[llama-hub]%s %s\n' "$_C_WRN" "$_C_RST" "$*" >&2; }
die()  { printf '%s[llama-hub]%s %s\n' "$_C_ERR" "$_C_RST" "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "falta el comando '$1'"; }

# `docker compose` (plugin) con respaldo a `docker-compose`.
llama_compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}

# -----------------------------------------------------------------------------
# HuggingFace: cabeceras, listado (con caché) y descarga
# -----------------------------------------------------------------------------
_LLAMA_HF_HDR=()
_llama_hf_hdr() {
    _LLAMA_HF_HDR=()
    if [[ -n "$HF_TOKEN" ]]; then
        _LLAMA_HF_HDR=(-H "Authorization: Bearer $HF_TOKEN")
    fi
    return 0
}

declare -A _LLAMA_HF_CACHE=()
llama_hf_files() {  # <repo> -> un rfilename por línea
    local repo="$1" out
    if [[ -n "${_LLAMA_HF_CACHE[$repo]:-}" ]]; then
        printf '%s\n' "${_LLAMA_HF_CACHE[$repo]}"
        return 0
    fi
    _llama_hf_hdr
    out="$(curl -fsSL ${_LLAMA_HF_HDR[@]+"${_LLAMA_HF_HDR[@]}"} \
                "https://huggingface.co/api/models/$repo" 2>/dev/null \
           | grep -o '"rfilename":"[^"]*"' \
           | sed 's/^"rfilename":"//; s/"$//' || true)"
    _LLAMA_HF_CACHE[$repo]="$out"
    printf '%s\n' "$out"
    return 0
}

llama_hf_context_length() {  # <repo> -> n_ctx_train del GGUF (o vacío si no consta)
    local repo="$1" out
    _llama_hf_hdr
    out="$(curl -fsSL ${_LLAMA_HF_HDR[@]+"${_LLAMA_HF_HDR[@]}"} \
                "https://huggingface.co/api/models/$repo?expand%5B%5D=gguf" 2>/dev/null \
           | grep -o '"context_length":[0-9]*' | head -n1 | sed 's/.*://' || true)"
    printf '%s\n' "$out"
    return 0
}

# Escapa metacaracteres de regex para poder buscar el texto como literal.
llama_regex_escape() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

_llama_grep_pat() {  # <patrón> [veto]  (lee de stdin)
    local pat="$1" veto="${2:-}"
    if [[ -n "$veto" ]]; then
        grep -iE "$pat" | grep -viE "$veto" || true
    else
        grep -iE "$pat" || true
    fi
}

llama_local_matches() {  # <dir> <patrón> [veto] -> rutas locales ordenadas
    local dir="$1" pat="$2" veto="${3:-}"
    { find "$dir" -maxdepth 1 -type f -iname '*.gguf' 2>/dev/null || true; } \
        | _llama_grep_pat "$pat" "$veto" | sort || true
}

llama_remote_matches() {  # <repo> <patrón> [veto] -> nombres remotos sin shards
    local repo="$1" pat="$2" veto="${3:-}"
    llama_hf_files "$repo" | _llama_grep_pat "$pat" "$veto" | grep -v -- '-of-' || true
}

llama_download() {  # <repo> <file> <dest>
    local repo="$1" file="$2" dest="$3"
    _llama_hf_hdr
    mkdir -p "$(dirname "$dest")"
    info "descargando $repo/$file"
    curl -fL --progress-bar -C - ${_LLAMA_HF_HDR[@]+"${_LLAMA_HF_HDR[@]}"} \
        -o "$dest.part" "https://huggingface.co/$repo/resolve/main/$file" \
        || die "falló la descarga: $repo/$file"
    mv -f "$dest.part" "$dest"
}

llama_ensure_file() {  # <repo> <patrón> [veto] -> ruta local (descarga si falta)
    local repo="$1" pat="$2" veto="${3:-}" hits file
    if hits="$(llama_local_matches "$MODELS_DIR" "$pat" "$veto")" && [[ -n "$hits" ]]; then
        printf '%s\n' "$hits" | head -n1
        return 0
    fi
    if file="$(llama_remote_matches "$repo" "$pat" "$veto")" && [[ -n "$file" ]]; then
        file="$(printf '%s\n' "$file" | head -n1)"
        llama_download "$repo" "$file" "$MODELS_DIR/$file"
        printf '%s\n' "$MODELS_DIR/$file"
        return 0
    fi
    return 1
}

llama_pick_quant() {  # <repo> <patrón1> [patrón2 ...] -> ruta local del GGUF
    local repo="$1"; shift
    local q hit
    for q in "$@"; do
        [[ -n "$q" ]] || continue
        # El patrón de cuantización se trata como literal (escapado) dentro del regex.
        if hit="$(llama_ensure_file "$repo" ".*$(llama_regex_escape "$q").*\.gguf" 'mmproj')"; then
            printf '%s\n' "$hit"
            return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# Cálculo de contexto y fichero de entorno del contenedor
# -----------------------------------------------------------------------------
llama_compute_ctx() {
    EFFECTIVE_CTX="${CTX_SIZE:-0}"
    if [[ "$EFFECTIVE_CTX" == 0 ]]; then
        EFFECTIVE_CTX=""
        info "contexto: el nativo del modelo (CTX_SIZE=0)"
        return 0
    fi
    if [[ -n "${MODEL_CTX_MAX:-}" && "$MODEL_CTX_MAX" -gt 0 && "$EFFECTIVE_CTX" -gt "$MODEL_CTX_MAX" ]]; then
        EFFECTIVE_CTX="$MODEL_CTX_MAX"
        info "contexto recortado al máximo del modelo: $EFFECTIVE_CTX"
    fi
}

llama_write_model_env() {
    mkdir -p "$RUN_DIR"
    chmod 700 "$RUN_DIR" 2>/dev/null || true
    local -a L=()

    L+=("LLAMA_ARG_MODEL=$MODEL_PATH")
    [[ -n "${MODEL_ALIAS:-}" ]] && L+=("LLAMA_ARG_ALIAS=$MODEL_ALIAS")

    if [[ -n "${MODEL_MMPROJ:-}" ]]; then
        L+=("LLAMA_ARG_MMPROJ=$MODEL_MMPROJ")
        [[ "$MMPROJ_TO_RAM" == true ]] && L+=("LLAMA_ARG_MMPROJ_OFFLOAD=false")
    fi

    L+=("LLAMA_ARG_HOST=$LLAMA_HOST")
    L+=("LLAMA_ARG_PORT=8080")
    [[ -n "${EFFECTIVE_CTX:-}" ]] && L+=("LLAMA_ARG_CTX_SIZE=$EFFECTIVE_CTX")
    L+=("LLAMA_ARG_CACHE_TYPE_K=$CACHE_TYPE_K")
    L+=("LLAMA_ARG_CACHE_TYPE_V=$CACHE_TYPE_V")
    L+=("LLAMA_ARG_FLASH_ATTN=$FLASH_ATTN")
    L+=("LLAMA_ARG_N_GPU_LAYERS=$N_GPU_LAYERS")

    # PLE a RAM: además del -ot, forzamos lazy-mode=off para que las tablas
    # queden residentes en memoria (RAM >> disco). Si no, con LAZY_MODE=auto/on
    # llama.cpp las leería de disco bajo demanda, justo lo que se quiere evitar.
    local lazy="$LAZY_MODE"
    if [[ "${PLE_MODEL:-false}" == true && "$PLE_TO_RAM" == true ]]; then
        L+=("LLAMA_ARG_OVERRIDE_TENSOR=per_layer_token_embd=CPU,per_layer_model_proj=CPU")
        lazy="off"
    fi
    L+=("LLAMA_ARG_LAZY_MODE=$lazy")

    [[ "$CPU_MOE" == true ]] && L+=("LLAMA_ARG_CPU_MOE=true")
    [[ "${N_CPU_MOE:-0}" != 0 ]] && L+=("LLAMA_ARG_N_CPU_MOE=$N_CPU_MOE")
    [[ "${MOE_CACHE_MIB:-0}" != 0 ]] && L+=("LLAMA_ARG_MOE_CACHE_MIB=$MOE_CACHE_MIB")

    [[ -n "$API_KEY" ]] && L+=("LLAMA_API_KEY=$API_KEY")

    if [[ -n "${MODEL_ENV_EXTRA[*]:-}" ]]; then
        L+=("${MODEL_ENV_EXTRA[@]}")
    fi

    printf '%s\n' "${L[@]}" > "$MODEL_ENV_FILE"
    # El fichero puede contener una API key: restringir a solo el usuario.
    chmod 600 "$MODEL_ENV_FILE" 2>/dev/null || true
    info "entorno del contenedor -> ${MODEL_ENV_FILE#"$LLAMA_HUB_ROOT"/}"
}

# -----------------------------------------------------------------------------
# Ciclo de vida del contenedor
# -----------------------------------------------------------------------------
llama_compose_up() {  # <backend>
    local backend="$1" file
    file="$(llama_compose_file "$backend")"
    [[ -f "$LLAMA_HUB_ROOT/$file" ]] || die "no existe el fichero de compose '$file'"
    (
        cd "$LLAMA_HUB_ROOT"
        llama_compose -f docker-compose.yml -f "$file" up -d --remove-orphans
    )
}

llama_compose_down() {
    (
        cd "$LLAMA_HUB_ROOT"
        llama_compose -f docker-compose.yml down --remove-orphans
    )
}

llama_summary() {
    info "listo · web UI: http://localhost:${PORT}/ · API: http://localhost:${PORT}/v1"
    info "logs: ./bin/status.sh  |  parar: ./bin/stop.sh"
}

# -----------------------------------------------------------------------------
# Orquestador que usan los scripts de serve/
# -----------------------------------------------------------------------------
llama_serve_model() {
    need_cmd docker
    need_cmd curl

    local backend
    backend="$(llama_resolve_backend "${1:-}")" || die "no se pudo resolver el backend"

    [[ -n "${MODEL_NAME:-}" && -n "${MODEL_REPO:-}" ]] \
        || die "el script de modelo debe definir MODEL_NAME y MODEL_REPO"

    info "modelo: ${MODEL_NAME}  ·  backend: ${backend}"

    local -a repos=("$MODEL_REPO")
    [[ -n "${MODEL_REPO_FALLBACK:-}" ]] && repos+=("$MODEL_REPO_FALLBACK")

    local -a quants=("${MODEL_QUANT:-Q4_K_M}")
    [[ -n "${MODEL_QUANT_FALLBACK:-}" ]] && quants+=("$MODEL_QUANT_FALLBACK")

    local weights="" matched_repo="" r
    for r in "${repos[@]}"; do
        if weights="$(llama_pick_quant "$r" "${quants[@]}")"; then
            matched_repo="$r"
            info "repositorio: $r"
            break
        fi
    done
    [[ -n "$weights" ]] || die "no se encontró cuantización en: ${repos[*]} (probado: ${quants[*]})"
    MODEL_PATH="/models/$(basename "$weights")"
    info "pesos: $(basename "$weights")"

    # 2) Proyector multimodal (opcional).
    MODEL_MMPROJ=""
    if [[ -n "${MODEL_MMPROJ_PATTERN:-}" ]]; then
        local mm
        for r in "${repos[@]}"; do
            if mm="$(llama_ensure_file "$r" "$MODEL_MMPROJ_PATTERN")"; then
                MODEL_MMPROJ="/models/$(basename "$mm")"
                info "mmproj: $(basename "$mm")"
                break
            fi
        done
        [[ -n "$MODEL_MMPROJ" ]] || warn "no se encontró mmproj en ${repos[*]} (arranco sin multimodal)"
    fi

    # 3) Contexto (máximo del modelo auto-detectado) + entorno + arranque.
    #    Se detecta del GGUF vía la API de HuggingFace; un MODEL_CTX_MAX definido en
    #    el script de modelo sigue teniendo prioridad si se quiere forzar.
    if [[ -z "${MODEL_CTX_MAX:-}" ]]; then
        MODEL_CTX_MAX="$(llama_hf_context_length "$matched_repo")"
        [[ -n "$MODEL_CTX_MAX" ]] && info "contexto máximo del modelo: $MODEL_CTX_MAX"
    fi

    llama_compute_ctx
    llama_write_model_env
    llama_compose_up "$backend"
    llama_summary "$backend"
}
