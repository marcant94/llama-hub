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
  expertos **MoE** en VRAM por defecto y, en MoE que no caben, expertos en RAM con
  **caché LRU de expertos calientes** en VRAM (`MOE_CACHE_MIB`).
- **KV cache cuantizado a `q8_0`** para ahorrar VRAM con pérdida mínima.
- Un **solo modelo activo a la vez** (contenedor fijo `llama-server`).
- Red **`proxylan`** compartida para visibilidad entre tus proyectos locales.
- Modelos en **`./models`** (bind mount), organizados en **una subcarpeta por repo**
  (`owner__repo/`) para que no colisionen ficheros con nombres genéricos
  (p. ej. `mmproj-BF16.gguf` de distintos modelos).

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
│   ├── gemma-4-26b-a4b.sh         #   MoE grande: expertos en RAM + caché en VRAM
│   ├── gemma-4-e2b.sh
│   ├── gemma-4-e4b.sh
│   ├── gpt-oss-20b.sh             #   MoE grande: expertos en RAM + caché en VRAM
│   ├── granite-4.0-h-tiny.sh
│   ├── ling-3.0-tiny.sh
│   ├── phi-4-mini-instruct.sh
│   └── qwen3-30b-a3b.sh           #   MoE grande: expertos en RAM + caché en VRAM
├── bin/                           # ← TÚ lo usas: utilidades (detect/download/list/status/stop)
│   ├── detect-backend.sh
│   ├── download.sh
│   ├── list-models.sh
│   ├── status.sh
│   └── stop.sh
├── lib/                           # NO se usa a mano: lógica interna (source de los otros)
│   ├── backend.sh
│   └── common.sh
├── models/                        # GGUFs descargados, en subcarpeta por repo (git-ignored)
├── .cache/nv/                     # caché JIT de CUDA persistente (git-ignored)
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
- **bash ≥ 4** en el host (para los arrays asociativos internos).
- Red `proxylan` creada (`docker network create proxylan` si no la tienes).
- Según el backend:
    - **NVIDIA**: `nvidia-container-toolkit`.
    - **AMD/Intel (Vulkan o ROCm)**: `/dev/dri` (y `/dev/kfd` para ROCm). El script
      detecta y añade automáticamente los grupos `video`/`render` del host; si tu
      host no define `render`, no pasa nada (simplemente no se añade).

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

Web UI en `http://localhost:18080/` y API OpenAI-compatible en
`http://localhost:18080/v1` (el puerto se cambia con `PORT` en `.env`).

## Backends

| `BACKEND` | Imagen | Extra de compose |
|---|---|---|
| `cpu` | `ghcr.io/ggml-org/llama.cpp:server` | — |
| `nvidia` | `ghcr.io/ggml-org/llama.cpp:server-cuda` | `runtime: nvidia`, `NVIDIA_VISIBLE_DEVICES` |
| `amd-vulkan` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | `/dev/dri`, grupos `video`/`render` (auto) |
| `amd-rocm` | `ghcr.io/ggml-org/llama.cpp:server-rocm` | `/dev/kfd` + `/dev/dri`, grupos `video`/`render` (auto) |
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

Todas son **opcionales** (tienen valor por defecto), así que el `.env` copiado tal cual
—el `.env.example` solo deja `BACKEND` activo y el resto comentadas— ya funciona.
Descomenta y ajusta solo las que necesites.

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND` | `auto` | `auto` \| `cpu` \| `nvidia` \| `amd-vulkan` \| `amd-rocm` |
| `LLAMA_SUFFIX` | *(vacío)* | Sufijo del tag de imagen para fijar un build (p. ej. `-b4667`). |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPUs NVIDIA visibles en el contenedor. |
| `AMD_RENDER_NODE` | `/dev/dri` | Nodo DRM del host mapeado a `/dev/dri`. |
| `LLAMA_HOST` | `0.0.0.0` | IP de escucha **dentro** del contenedor. |
| `PORT` | `18080` | Puerto publicado en el host (el contenedor escucha en 8080 dentro). |
| `API_KEY` | *(vacío)* | API key opcional (vacío = sin auth). |
| `MEM_LIMIT` | `0` | Límite de RAM del contenedor en bytes (`0` = sin límite). |
| `CPUS` | `0` | Límite de CPUs (`0` = sin límite). |
| `RESTART_POLICY` | `no` | `no` \| `unless-stopped` \| `always` \| `on-failure`. |
| `HEALTH_START_PERIOD` | `300s` | Espera antes de contar fallos del healthcheck (evita `unhealthy` mientras carga el modelo). |
| `MODELS_DIR` | `./models` | Carpeta local de los `.gguf` (relativa al repo, absoluta o con `~`). |
| `CUDA_CACHE_DIR` | `./.cache/nv` | Caché JIT de CUDA persistente. Evita que la primera inferencia recompile kernels (~decenas de segundos) tras **recrear** el contenedor. |
| `HF_TOKEN` | *(vacío)* | Token de HuggingFace (solo repos gated/privados). |
| `PLE_TO_RAM` | `true` | Desvía las tablas PLE (Gemma 4 E2B/E4B) a RAM. |
| `MMPROJ_TO_RAM` | `true` | Desvía el proyector multimodal a RAM. |
| `N_GPU_LAYERS` | `all` | Capas a VRAM: `N` \| `auto` \| `all`. |
| `SPEC_NGRAM` | `true` | Drafting por n-gramas (`ngram-mod`), activo para **todos** los modelos. Medido en Vulkan: nunca más lento (Granite 44.5 → 44.5 en prosa y 44.8 → 122 en repetitivo; Gemma 52 → 56 y 52 → 130). Ojo: el drafting **puede cambiar la salida** respecto a sin draft; solo sin speculative es determinista. El **draft externo/MTP** sí se descarta: en híbridos es inviable (15 t/s en Granite) y el MTP de Gemma solo gana en código/repetitivo y pierde en prosa. |
| `CTX_SIZE` | `32768` | Contexto preferido (`0` = nativo del modelo). |
| `CACHE_TYPE_K` | `q8_0` | Tipo del KV cache (K). |
| `CACHE_TYPE_V` | `q8_0` | Tipo del KV cache (V). |
| `FLASH_ATTN` | `on` | `on` \| `off` \| `auto`. Requerido para KV cuantizado. |
| `LAZY_MODE` | `off` | `on` \| `auto` \| `off`. Lectura de tensores grandes desde disco (forzado a `off` en modelos PLE con `PLE_TO_RAM=true`). |
| `LOAD_MODE` | *(vacío)* | `auto` \| `none` \| `mmap` \| `mlock` \| `mmap+mlock` \| `dio`. Vacío = `auto`. `none` = leer a RAM sin mmap (evita la penalización de `-ot` a CPU con mmap); con `PLE_TO_RAM=true` se usa `none` automáticamente. **En Vulkan/AMD `none` manda los pesos a GTT, no a RAM normal** (ver [docs/flags.md](docs/flags.md)). |
| `CPU_MOE` | `false` | `true` = todos los expertos MoE a RAM (opt-in). |
| `N_CPU_MOE` | `0` | `N` > 0 = expertos de las primeras N capas a RAM (opt-in). |
| `MOE_CACHE_MIB` | `0` | Caché de expertos "calientes" en VRAM (MiB). **Solo actúa junto con `CPU_MOE`/`N_CPU_MOE`** (si los expertos ya están en VRAM no hay nada que cachear). |
| `MODEL_CPU_MOE` | — | Default de `CPU_MOE` para un modelo concreto (`serve/*.sh`). El `.env` sigue mandando si tiene otro valor. |
| `MODEL_N_CPU_MOE` | — | Default de `N_CPU_MOE` para un modelo concreto (`serve/*.sh`). |
| `MODEL_MOE_CACHE_MIB` | — | Default de `MOE_CACHE_MIB` para un modelo concreto (`serve/*.sh`). |

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
  `-ot per_layer_token_embd=CPU,per_layer_model_proj=CPU`, fuerza `--lazy-mode off`
  y usa `--load-mode none` (evita la penalización de los overrides a CPU con mmap)
  para que la tabla quede **residente en RAM** (RAM ≫ disco).
- **mmproj → RAM**: `MMPROJ_TO_RAM=true` añade `--no-mmproj-offload`.
- **MoE → VRAM** por defecto. Si el modelo no cabe, hay dos escalones:
    - `N_CPU_MOE=N` → expertos de las **primeras N capas** a RAM (así el resto
      siguen en VRAM, que es lo más rápido).
    - `CPU_MOE=true` → **todos** los expertos a RAM.
- **MoE grande + `MOE_CACHE_MIB`** (la receta de `serve/gemma-4-26b-a4b.sh`,
  `serve/gpt-oss-20b.sh` y `serve/qwen3-30b-a3b.sh`): con los expertos en RAM,
  `MOE_CACHE_MIB=N` reserva N MiB de VRAM para una **caché LRU de expertos**: los
  pares (capa, experto) más usados se quedan residentes y los fríos se desalojan,
  subiéndose por PCIe solo cuando se necesitan. La generación (≤32 tokens) es la
  única que actualiza ese LRU, así que un prompt largo **no** desaloja los expertos
  calientes del chat. Dimensionado: `denso + KV + MOE_CACHE_MIB + buffers ≈ VRAM`,
  teniendo en cuenta que el **pico** (prefill) es ~0,4 GB mayor que la media.

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
MODEL_CPU_MOE=true               # opcional: todos los expertos a RAM (MoE grande)
MODEL_MOE_CACHE_MIB=3800         # opcional: caché LRU de expertos en VRAM (MiB)
MODEL_CTX_MAX=32768              # opcional: tope de contexto (protege la VRAM)
MODEL_ENV_EXTRA=()               # líneas LLAMA_ARG_* extra

llama_serve_model "$@"
```

Dale permisos de ejecución (`chmod +x serve/<tu-modelo>.sh`) y listo.

El script resuelve el nombre exacto del fichero consultando la API de HuggingFace,
así que no necesitas acertar con el nombre completo de la cuantización, y **detecta
solo** el contexto máximo del modelo (metadatos GGUF). Si quisieras forzarlo, define
`MODEL_CTX_MAX` en el propio script.

`MODEL_CPU_MOE`, `MODEL_N_CPU_MOE` y `MODEL_MOE_CACHE_MIB` son solo **defaults del
modelo**: si defines `CPU_MOE`, `N_CPU_MOE` o `MOE_CACHE_MIB` en el `.env`, esos
valores tienen prioridad. Mira `serve/gemma-4-26b-a4b.sh` como ejemplo con las
cuentas de VRAM comentadas.

## API

- `GET /health` — estado.
- `GET /props` — propiedades del modelo cargado.
- `GET /v1/models` — modelos disponibles (alias).
- `POST /v1/chat/completions` — OpenAI-compatible.
- Web UI en `/`.

Ejemplo:

```bash
curl -s http://localhost:18080/v1/chat/completions \
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
- **`unable to find group render`** (AMD) → los grupos se añaden por GID numérico
  del host (Docker resuelve los *nombres* contra el /etc/group de la imagen, que no
  trae `render`). Actualiza tu copia del repo; si aun así fallara, fuerza el GID con
  `RENDER_GID=$(getent group render | cut -d: -f3)` en el entorno o en `.env`.
- **OOM de VRAM** → baja `N_GPU_LAYERS`, usa una cuantización menor, activa el
  offload de MoE a RAM (`N_CPU_MOE`) o baja `MOE_CACHE_MIB` (es lo que más VRAM
  consume cuando está activo).
- **Saber si el caché de expertos acierta** → `llama-server` **no** imprime ese
  informe (su logger lo descarta). Usa las herramientas del contenedor con `-lv 4`,
  que sí lo vuelcan al terminar: `llama completion`, `cli`, `perplexity` o
  `batched-bench` (con `-cmoe`/`-ncmoe` y `--moe-cache-mib`). Ejemplo y salida real
  medida en [`docs/flags.md`](docs/flags.md).
- **La RAM no sube aunque el modelo es enorme** → normal con `mmap`: el GGUF no se
  copia a RAM, se mapea, y sus páginas quedan en la **caché de páginas** (`free` →
  `búf/caché`). Medido aquí: 17,1 GB residentes y 0,1 MB de disco por generación. Ojo
  si usas `LOAD_MODE=none` para "verla": en **Vulkan/AMD** eso manda los pesos a
  **GTT** (tope ~la mitad de la RAM), así que un MoE de 17 GB no cabe y el contenedor
  muere con `device lost`. Detalles medidos en [`docs/flags.md`](docs/flags.md).
- **NVIDIA no acelera** → comprueba `nvidia-container-toolkit` y que `BACKEND=nvidia`.
- **MMProj a RAM y quieres velocidad** → pon `MMPROJ_TO_RAM=false`.
- **Sin GPU** → `BACKEND=cpu` (o deja `auto` sin `/dev/dri` ni NVIDIA).
