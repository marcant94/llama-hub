# Referencia de flags y variables de entorno

`llama-hub` no pasa flags por línea de comandos: configura el contenedor con
**variables de entorno nativas de llama.cpp**. El script de cada modelo genera el
fichero `.run/model.env` con las variables resueltas, y `docker-compose` lo inyecta
en el contenedor.

- Columna **Flag**: el equivalente en línea de comandos de `llama-server`.
- Columna **Variable**: la variable de entorno que usa `llama-hub`.
- Columna **Dónde**: `.env` = configuración global; `serve/<modelo>.sh` = por modelo.

---

## Modelo y rutas

| Variable | Flag | Qué hace | Dónde |
|---|---|---|---|
| `LLAMA_ARG_MODEL` | `-m, --model` | Ruta del `.gguf` dentro del contenedor (`/models/...`). | generada |
| `LLAMA_ARG_MMPROJ` | `-mm, --mmproj` | Proyector multimodal (visión/audio). | generada |
| `LLAMA_ARG_MMPROJ_OFFLOAD` | `--no-mmproj-offload` | `false` = mmproj en RAM en vez de VRAM. | `.env` (`MMPROJ_TO_RAM`) |
| `MTMD_BACKEND_DEVICE` | `-mmdev, --mmproj-device` | Dispositivo del mmproj (`none` = no offload). Alternativa al anterior. | — |
| `LLAMA_ARG_ALIAS` | `-a, --alias` | Nombre del modelo expuesto por la API. | `serve/*.sh` |

## Servidor

| Variable | Flag | Qué hace | Dónde |
|---|---|---|---|
| `LLAMA_ARG_HOST` | `--host` | IP de escucha dentro del contenedor (`0.0.0.0`). | `.env` |
| `LLAMA_ARG_PORT` | `--port` | Puerto interno (siempre `8080`; el host lo mapea a `PORT`). | generada |
| `LLAMA_API_KEY` | `--api-key` | API key para proteger el endpoint (admite lista separada por comas). | `.env` (`API_KEY`) |
| `LLAMA_ARG_JINJA` | `--jinja / --no-jinja` | Motor de plantillas Jinja para el chat (activado por defecto). | `.env`/modelo |

## Contexto y rendimiento

| Variable | Flag | Qué hace | Dónde |
|---|---|---|---|
| `LLAMA_ARG_CTX_SIZE` | `-c, --ctx-size` | Tamaño de contexto en tokens. `0` = el nativo del modelo. | `.env` (`CTX_SIZE`) |
| `LLAMA_ARG_N_GPU_LAYERS` | `-ngl, --n-gpu-layers` | Capas en VRAM: `N`, `auto` o `all`. | `.env` (`N_GPU_LAYERS`) |
| `LLAMA_ARG_FLASH_ATTN` | `-fa, --flash-attn` | `on`/`off`/`auto`. **Requerido** para KV cache cuantizado. | `.env` (`FLASH_ATTN`) |
| `LLAMA_ARG_CACHE_TYPE_K` | `-ctk, --cache-type-k` | Tipo del KV cache (K). `q8_0` ahorra ~mitad de VRAM del KV. | `.env` (`CACHE_TYPE_K`) |
| `LLAMA_ARG_CACHE_TYPE_V` | `-ctv, --cache-type-v` | Tipo del KV cache (V). | `.env` (`CACHE_TYPE_V`) |
| `LLAMA_ARG_LAZY_MODE` | `-lzm, --lazy-mode` | `on`/`auto`/`off`. `on` lee de disco bajo demanda los tensores grandes (p. ej. PLE); `off` los mantiene residentes. | `.env` (`LAZY_MODE`) |
| `LLAMA_ARG_LOAD_MODE` | `-lm, --load-mode` | `auto`/`none`/`mmap`/`mlock`/`mmap+mlock`/`dio`. `none` = leer a RAM sin mmap (evita la penalización de `-ot` a CPU con mmap). | `.env` (`LOAD_MODE`; `none` automático en PLE) |

Valores válidos de KV cache: `f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1`.

> El máximo del modelo (`n_ctx_train`) se detecta automáticamente de los metadatos GGUF
> vía la API de HuggingFace; el contexto efectivo es `min(CTX_SIZE, máximo)`. Con
> `CTX_SIZE=0` se usa el nativo del modelo sin recortar. Un `MODEL_CTX_MAX` definido en
> el script de modelo tiene prioridad sobre la detección.

## Speculative decoding (drafting)

| Variable | Flag | Qué hace | Dónde |
|---|---|---|---|
| `LLAMA_ARG_SPEC_TYPE` | `--spec-type` | Tipo de drafting: `draft-simple` (draft externo), `draft-mtp` (MTP del propio modelo), `ngram-mod` (hash de n-gramas, ~16 MB). | generada |
| `LLAMA_ARG_SPEC_DRAFT_MODEL` | `-md, --model-draft` | Fichero del draft model (o del drafter MTP). Ningún `serve/*.sh` lo usa por defecto. | opcional |
| `LLAMA_ARG_SPEC_DRAFT_N_MAX` | `--spec-draft-n-max` | Tokens a proponer por draft (default 3). Solo con draft externo/MTP. | opcional |
| `LLAMA_ARG_N_GPU_LAYERS_DRAFT` | `-ngld, --n-gpu-layers-draft` | Capas del draft en VRAM (`0` = draft en CPU). Solo con draft externo/MTP. | opcional |

> El target **verifica** cada token draft, así que la ganancia depende de la tasa de
> aceptación. Draft externo requiere mismo tokenizer (misma familia). Con MoE el doc
> de llama.cpp recomienda drafts largos.
>
> Medido en RX 6650 XT (Vulkan), Gemma 4 E4B, 150 tokens (máquina libre):
>
> | Prompt | `none` | `ngram-mod` | `draft-mtp` | `ngram-mod,draft-mtp` |
> |---|---|---|---|---|
> | Prosa | 52 | 56 | 40 | 45 |
> | Código | 52 | 56 | 56 | 65 |
> | Repetitivo | 52 | 130 | 93 | 197 |
> | Resumen | 52 | 55 | 44 | 51 |
>
> `ngram-mod` no fue más lento en ningún caso; `draft-mtp` solo gana con aceptación
> alta (código/repetitivo) y pierde en prosa. **Ningún modo de drafting garantiza una
> salida idéntica a sin draft** (verificado por md5: solo `none` es determinista;
> `ngram-mod` y `draft-mtp` divergen de forma reproducible). Por eso Gemma 4 usa
> `ngram-mod`: más rápido aquí y sin modelo extra.
>
> **Draft externo en modelos híbridos/recurrentes (Mamba, p. ej. Granite 4.0 H):
> no compensa.** El contexto no admite `seq_rm` parcial, así que cada aceptación
> parcial obliga a restaurar un *checkpoint completo del estado recurrente*
> (+ replay); con drafts cortos y aceptación mediocre eso ocurre casi en cada paso.
> Medido en RX 6650 XT (Vulkan) con Granite 4.0 H: **15 t/s** con `draft-simple`
> frente a ~45 t/s del target solo. El `ngram-mod` **no** paga ese coste (en prosa
> no propone nada; en repetitivo acepta drafts largos enteros, sin rollback
> parcial): 44.5 → 44.5 t/s en prosa y 44.8 → 121.8 t/s en repetitivo. Por eso
> Granite usa `ngram-mod` (por defecto) y descarta el draft externo.
>
> Los números absolutos varían bastante entre sesiones (carga de CPU, temperatura):
> compara siempre configs **intercaladas dentro de la misma tanda**.

## Desvío a memoria (offload selectivo)

| Variable | Flag | Qué hace | Dónde |
|---|---|---|---|
| `LLAMA_ARG_OVERRIDE_TENSOR` | `-ot, --override-tensor` | Fuerza el buffer de tensores que casen con un patrón (`patrón=tipo[,...]`). Tipos de buffer: `CPU`, `CUDA0`, `Vulkan0`, `ROCm0`. | `serve/*.sh` (PLE) |
| `LLAMA_ARG_CPU_MOE` | `-cmoe, --cpu-moe` | Mantiene **todos** los expertos MoE en CPU. | `.env` (`CPU_MOE`) |
| `LLAMA_ARG_N_CPU_MOE` | `-ncmoe, --n-cpu-moe` | Mantiene en CPU los expertos de las **primeras N** capas. | `.env` (`N_CPU_MOE`) |
| `LLAMA_ARG_MOE_CACHE_MIB` | `--moe-cache-mib` | Caché en GPU (MiB) para expertos "calientes" cuando hay offload a CPU. | `.env` (`MOE_CACHE_MIB`) |
| `LLAMA_ARG_N_CPU_FFN` | `-ncffn, --n-cpu-ffn` | Mantiene en CPU el FFN denso de las **primeras N** capas (modelos densos). | — |

> Los expertos MoE son operaciones de cómputo: sacarlos a RAM obliga a transferirlos
> por PCIe en cada token y **penaliza mucho**. Por eso `llama-hub` los deja en VRAM
> por defecto y el offload es opt-in.

## Muestreo y chat (opcional, por modelo)

| Variable | Flag | Qué hace |
|---|---|---|
| `LLAMA_ARG_TEMPERATURE` | `--temp` | Temperatura de muestreo. |
| `LLAMA_ARG_TOP_K` | `--top-k` | Top-K. |
| `LLAMA_ARG_TOP_P` | `--top-p` | Top-P (nucleus). |
| `LLAMA_ARG_REASONING` | `-rea, --reasoning` | `on`/`off`/`auto`: uso del modo "thinking". |
| `LLAMA_ARG_REASONING_EFFORT` | `--reasoning-effort` | Nivel de esfuerzo de razonamiento. |

> Solo algunos `serve/*.sh` fijan estos valores como *defaults del servidor* (el cliente
> puede sobrescribirlos por petición): `gemma-4-e2b`/`gemma-4-e4b` (receta oficial de
> Google: `temperature=1.0`, `top_k=64`, `top_p=0.95`) y `phi-4-mini-instruct`
> (`temperature=0.0`, greedy) — receta oficial de Microsoft. `ling-3.0-tiny` y
> `granite-4.0-h-tiny` no fijan nada y usan los defaults de llama.cpp.

---

## PLE (Per-Layer Embeddings) de Gemma 4 E2B/E4B

Gemma 4 E2B/E4B añaden, por capa, pequeñas tablas de embeddings por token. Son
**grandes pero solo se consultan** (lookups). Tensor implicado (nombre GGUF):

- `per_layer_token_embd` — la tabla grande (la que interesa desviar).
- `per_layer_model_proj`, `per_layer_proj_norm` — proyecciones asociadas (pequeñas).

Con `PLE_TO_RAM=true`, `llama-hub` aplica:

```
LLAMA_ARG_OVERRIDE_TENSOR=per_layer_token_embd=CPU,per_layer_model_proj=CPU
LLAMA_ARG_LAZY_MODE=off
```

Resultado: la parte activa va a VRAM (`-ngl`) y las tablas PLE quedan residentes en
RAM. `LAZY_MODE=off` evita que se lean de disco (más lento). Si prefieres ahorrar
RAM y tienes SSD, puedes probar `PLE_TO_RAM=false` + `LAZY_MODE=auto` (no usar con HDD).

## Comprobar los nombres de buffer/dispositivo

Los nombres válidos para `-ot` dependen del backend. Para verlos:

```bash
docker run --rm ghcr.io/ggml-org/llama.cpp:server-vulkan --list-devices
```

Saldrán entradas como `CPU`, `Vulkan0`. En CUDA, `CUDA0`; en ROCm, `ROCm0`.
