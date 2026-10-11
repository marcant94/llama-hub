# llama-hub

Hub dockerizado de **llama.cpp / llama-server** con soporte para **CPU, GPU NVIDIA
(CUDA), AMD nativa (ROCm) y AMD/Intel vía Vulkan** — los cuatro modos — y **un script
por modelo** que descarga el GGUF (y su proyector multimodal) si falta y lo arranca
con su configuración de flags.

Pensado para ser genérico y portable: no hay nada atado a una máquina concreta, el
backend se elige con una variable (o se autodetecta) y los modelos viven en una
carpeta local visible.

## Características

- **4 backends** con imágenes oficiales precompiladas de llama.cpp (sin compilar nada).
- **Un `.sh` por modelo** (`serve/`) con sus flags propios.
- **Descarga automática** de pesos y `mmproj` desde HuggingFace (idempotente, con
  reanudación si se corta).
- **Offload selectivo**: parte activa en VRAM, tablas **PLE** y **mmproj** en RAM,
  expertos **MoE** en VRAM por defecto.
- **KV cache cuantizado a `q8_0`** para ahorrar VRAM con pérdida mínima.
- Un **solo modelo activo a la vez** (contenedor fijo `llama-server`).
- Red **`proxylan`** compartida para visibilidad entre tus proyectos locales.
- Modelos en **`./models`** (bind mount), no en un volumen opaco de Docker.

## Estructura

```
llama-hub/
├── docker-compose.yml             # base (modo CPU)
├── compose/                       # overrides por backend (heredan del base)
│   ├── docker-compose.cpu.yml
│   ├── docker-compose.nvidia.yml  #   override NVIDIA (CUDA)
│   ├── docker-compose.amd-vulkan.yml
│   └── docker-compose.amd-rocm.yml
├── .env.example                   # plantilla de configuración -> copiar a .env
├── README.md
├── docs/flags.md                  # referencia de flags y variables
├── serve/                         # ← TÚ lo usas: un script por modelo
│   ├── gemma-4-e2b.sh
│   ├── gemma-4-e4b.sh
│   └── ling-3.0-tiny.sh
├── bin/                           # ← TÚ lo usas: utilidades (detect/download/list/status/stop)
│   ├── detect-backend.sh
│   ├── download.sh
│   ├── list-models.sh
│   ├── status.sh
│   └── stop.sh
├── lib/                           # NO se usa a mano: lógica interna (source de los otros)
│   ├── backend.sh
│   └── common.sh
├── models/                        # GGUFs descargados (git-ignored)
└── .run/                          # entorno del contenedor generado (git-ignored)
```

**¿Quién usa cada carpeta?**

- **`serve/`** — los scripts que tú ejecutas para arrancar cada modelo.
- **`bin/`** — utilidades que ejecutas tú (estado, parar, descargar, listar).
- **`lib/`** — **no se ejecuta**: es el código que `serve/` y `bin/` importan
  (`source lib/common.sh`). No lo toques salvo para desarrollar.
- **`compose/`** — no se ejecuta directamente: lo usa `lib/common.sh` para levantar el
  contenedor con el backend elegido. Puedes invocarlo a mano si sabes lo que haces
  (ver "Uso avanzado de compose" más abajo).

No ejecutas nada de `lib/` ni `compose/`; solo `serve/` y `bin/`.

## Requisitos

- **Docker** con el plugin `docker compose` (o `docker-compose`).
- **curl** en el host.
- Red `proxylan` creada (`docker network create proxylan` si no la tienes).
- Según el backend:
    - **NVIDIA**: `nvidia-container-toolkit`.
    - **AMD/Intel (Vulkan o ROCm)**: `/dev/dri` (y `/dev/kfd` para ROCm); grupos
      `video` y `render`. Si tu host no tiene el grupo `render`, elimina el bloque
      `group_add` del override correspondiente.

## Inicio rápido

```bash
cp .env.example .env          # ajusta BACKEND y lo que necesites
./serve/gemma-4-e4b.sh        # descarga (si hace falta) y arranca con backend auto
./bin/status.sh               # estado + health + modelo cargado
./bin/stop.sh                 # parar
```

Cambiar de modelo = ejecutar otro `serve/<modelo>.sh` (recrea el contenedor).
Forzar un backend puntual:

```bash
./serve/gemma-4-e4b.sh vulkan     # o cpu | nvidia | amd-vulkan | amd-rocm
```

Web UI en `http://localhost:8080/` y API OpenAI-compatible en
`http://localhost:8080/v1`.

## Backends

| `BACKEND` | Imagen | Extra de compose |
|---|---|---|
| `cpu` | `ghcr.io/ggml-org/llama.cpp:server` | — |
| `nvidia` | `ghcr.io/ggml-org/llama.cpp:server-cuda` | `runtime: nvidia`, `NVIDIA_VISIBLE_DEVICES` |
| `amd-vulkan` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | `/dev/dri`, grupos `video`/`render` |
| `amd-rocm` | `ghcr.io/ggml-org/llama.cpp:server-rocm` | `/dev/kfd` + `/dev/dri`, grupos `video`/`render` |
| `auto` | — | NVIDIA→`nvidia`, `/dev/dri`→`amd-vulkan`, si no→`cpu` |

> `amd-rocm` hay que forzarlo: `auto` nunca lo elige (muchas GPUs AMD de consumo no
> están soportadas por ROCm; para esas, Vulkan es el camino correcto).

## Utilidades (`bin/`)

| Script | Qué hace |
|---|---|
| `detect-backend.sh` | Imprime el backend que se usaría con `auto`. |
| `download.sh <repo> <patrón> [veto]` | Descarga un `.gguf` concreto a `models/`. |
| `list-models.sh` | Lista los `.gguf` descargados con su tamaño. |
| `status.sh [-f]` | Estado del contenedor + health + modelo/contexto (`-f` sigue logs). |
| `stop.sh` | Para y elimina el contenedor. |

## Variables de `.env`

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND` | `auto` | `auto` \| `cpu` \| `nvidia` \| `amd-vulkan` \| `amd-rocm` |
| `LLAMA_SUFFIX` | *(vacío)* | Sufijo del tag de imagen para fijar un build (p. ej. `-b4667`). |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPUs NVIDIA visibles en el contenedor. |
| `AMD_RENDER_NODE` | `/dev/dri` | Nodo DRM del host mapeado a `/dev/dri`. |
| `LLAMA_HOST` | `0.0.0.0` | IP de escucha **dentro** del contenedor. |
| `PORT` | `8080` | Puerto publicado en el host. |
| `API_KEY` | *(vacío)* | API key opcional (vacío = sin auth). |
| `MEM_LIMIT` | `0` | Límite de RAM del contenedor en bytes (`0` = sin límite). |
| `CPUS` | `0` | Límite de CPUs (`0` = sin límite). |
| `RESTART_POLICY` | `no` | `no` \| `unless-stopped` \| `always` \| `on-failure`. |
| `MODELS_DIR` | `./models` | Carpeta local de los `.gguf` (relativa al repo, absoluta o con `~`). |
| `HF_TOKEN` | *(vacío)* | Token de HuggingFace (solo repos gated/privados). |
| `PLE_TO_RAM` | `true` | Desvía las tablas PLE (Gemma 4 E2B/E4B) a RAM. |
| `MMPROJ_TO_RAM` | `true` | Desvía el proyector multimodal a RAM. |
| `N_GPU_LAYERS` | `all` | Capas a VRAM: `N` \| `auto` \| `all`. |
| `CTX_SIZE` | `32768` | Contexto preferido (`0` = nativo del modelo). |
| `CACHE_TYPE_K` | `q8_0` | Tipo del KV cache (K). |
| `CACHE_TYPE_V` | `q8_0` | Tipo del KV cache (V). |
| `FLASH_ATTN` | `on` | `on` \| `off` \| `auto`. Requerido para KV cuantizado. |
| `LAZY_MODE` | `off` | `on` \| `auto` \| `off`. Lectura de tensores grandes desde disco (forzado a `off` en modelos PLE con `PLE_TO_RAM=true`). |
| `CPU_MOE` | `false` | `true` = todos los expertos MoE a CPU (opt-in). |
| `N_CPU_MOE` | `0` | `N` > 0 = expertos de las primeras N capas a CPU (opt-in). |
| `MOE_CACHE_MIB` | `0` | Caché en GPU (MiB) para expertos "calientes" con offload a CPU. |

> **Contexto**: el máximo del modelo (`n_ctx_train`) se **detecta automáticamente** de
> los metadatos GGUF (API de HuggingFace) y el contexto efectivo es
> `min(CTX_SIZE, máximo del modelo)`. Con `CTX_SIZE=0` se usa el contexto **nativo** del
> modelo sin recortar (comportamiento tipo Ollama). No hay que mantener ningún valor
> por modelo; si quieres forzarlo, basta con definir `MODEL_CTX_MAX` en el `serve/*.sh`.

Detalle de cada flag de llama.cpp equivalente en [`docs/flags.md`](docs/flags.md).

## Cómo funciona el offload selectivo

- **Parte activa → VRAM**: `N_GPU_LAYERS` (`-ngl`). Ponlo a un número menor si no
  cabe todo en VRAM.
- **PLE → RAM** (Gemma 4 E2B/E4B): `PLE_TO_RAM=true` añade
  `-ot per_layer_token_embd=CPU,per_layer_model_proj=CPU` y fuerza `--lazy-mode off`
  para que la tabla quede **residente en RAM** (RAM ≫ disco).
- **mmproj → RAM**: `MMPROJ_TO_RAM=true` añade `--no-mmproj-offload`.
- **MoE → VRAM** por defecto. Si no te cabe el modelo, activa `N_CPU_MOE` (o
  `CPU_MOE`) y opcionalmente `MOE_CACHE_MIB`; sopesa la pérdida de velocidad.

## Añadir un modelo

Crea `serve/<tu-modelo>.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODEL_ALIAS="mi-modelo"
MODEL_REPO="usuario/repo-GGUF"
MODEL_QUANT="Q4_K_M"            # patrón preferido (o UD-Q4_K_XL, etc.)
MODEL_QUANT_FALLBACK="Q5_K_M"   # opcional
MODEL_MMPROJ_PATTERN=""          # p. ej. "mmproj.*\.gguf" si es multimodal
PLE_MODEL=false                  # true solo para Gemma 4 E2B/E4B
MODEL_ENV_EXTRA=()               # líneas LLAMA_ARG_* extra

llama_serve_model "$@"
```

Dale permisos de ejecución (`chmod +x serve/<tu-modelo>.sh`) y listo.

El script resuelve el nombre exacto del fichero consultando la API de HuggingFace,
así que no necesitas acertar con el nombre completo de la cuantización, y **detecta
solo** el contexto máximo del modelo (metadatos GGUF). Si quisieras forzarlo, define
`MODEL_CTX_MAX` en el propio script.

## API

- `GET /health` — estado.
- `GET /props` — propiedades del modelo cargado.
- `GET /v1/models` — modelos disponibles (alias).
- `POST /v1/chat/completions` — OpenAI-compatible.
- Web UI en `/`.

Ejemplo:

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemma-4-e4b","messages":[{"role":"user","content":"Hola"}]}'
```

## Uso avanzado de compose

Normalmente no hace falta (lo hace `serve/<modelo>.sh` por ti), pero puedes
combinar el fichero base con el override del backend a mano:

```bash
docker compose -f docker-compose.yml -f compose/docker-compose.nvidia.yml up -d
docker compose -f docker-compose.yml -f compose/docker-compose.amd-vulkan.yml up -d
docker compose -f docker-compose.yml -f compose/docker-compose.amd-rocm.yml up -d
docker compose -f docker-compose.yml -f compose/docker-compose.cpu.yml up -d
docker compose -f docker-compose.yml down   # parar
```

Ten en cuenta que el contenedor lee su configuración de `.run/model.env`, que genera
`serve/<modelo>.sh`; si levantas compose a mano sin haber generado ese fichero, no
habrá modelo que cargar.

## Solución de problemas

- **`network proxylan not found`** → `docker network create proxylan`.
- **`unable to find group render`** (AMD) → elimina `group_add` del override AMD.
- **OOM de VRAM** → baja `N_GPU_LAYERS`, usa una cuantización menor o activa el
  offload de MoE a CPU (`N_CPU_MOE`).
- **NVIDIA no acelera** → comprueba `nvidia-container-toolkit` y que `BACKEND=nvidia`.
- **MMProj a RAM y quieres velocidad** → pon `MMPROJ_TO_RAM=false`.
- **Sin GPU** → `BACKEND=cpu` (o deja `auto` sin `/dev/dri` ni NVIDIA).
