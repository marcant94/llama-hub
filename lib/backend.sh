#!/usr/bin/env bash
# =============================================================================
# llama-hub — detección y resolución del backend (los "4 modos").
# Se hace `source` desde lib/common.sh.
# =============================================================================

# Backends soportados y fichero de override de compose asociado.
LLAMA_BACKENDS=(cpu nvidia amd-vulkan amd-rocm)

# Detección automática del backend según el hardware disponible en el host.
llama_detect_backend() {
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        printf 'nvidia\n'
        return 0
    fi
    if [[ -d /dev/dri ]]; then
        # AMD/Intel: Vulkan es el camino genérico (ROCm solo en GPUs soportadas).
        printf 'amd-vulkan\n'
        return 0
    fi
    printf 'cpu\n'
}

# resolve_backend [forzado]
#   Imprime el backend efectivo (auto -> detección, alias -> nombre canónico).
llama_resolve_backend() {
    local b="${1:-${BACKEND:-auto}}"

    case "$b" in
        '' | auto) b="$(llama_detect_backend)" ;;
        amd | vulkan) b="amd-vulkan" ;;
        rocm) b="amd-rocm" ;;
    esac

    case "$b" in
        cpu | nvidia | amd-vulkan | amd-rocm)
            printf '%s\n' "$b"
            ;;
        *)
            printf "backend no válido: '%s' (usa: auto|cpu|nvidia|amd-vulkan|amd-rocm)\n" "$b" >&2
            return 1
            ;;
    esac
}

# llama_compose_file <backend> -> nombre del fichero de override (relativo al repo).
llama_compose_file() {
    printf 'compose/docker-compose.%s.yml\n' "$1"
}
