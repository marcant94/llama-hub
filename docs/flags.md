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
| `LLAMA_ARG_LOAD_MODE` | `-lm, --load-mode` | `auto`/`none`/`mmap`/`mlock`/`mmap+mlock`/`dio`. `none` = leer a RAM sin mmap (evita la penalización de `-ot` a CPU con mmap). **En Vulkan/AMD va a GTT, no a RAM normal.** | `.env` (`LOAD_MODE`; `none` automático en PLE) |

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
| `LLAMA_ARG_CPU_MOE` | `-cmoe, --cpu-moe` | Mantiene **todos** los expertos MoE en RAM. | `.env` (`CPU_MOE`) / `serve/*.sh` (`MODEL_CPU_MOE`) |
| `LLAMA_ARG_N_CPU_MOE` | `-ncmoe, --n-cpu-moe` | Mantiene en RAM los expertos de las **primeras N** capas. | `.env` (`N_CPU_MOE`) / `serve/*.sh` (`MODEL_N_CPU_MOE`) |
| `LLAMA_ARG_MOE_CACHE_MIB` | `--moe-cache-mib` | Caché LRU de expertos "calientes" en VRAM (MiB). Solo actúa con `CPU_MOE`/`N_CPU_MOE`. | `.env` (`MOE_CACHE_MIB`) / `serve/*.sh` (`MODEL_MOE_CACHE_MIB`) |
| `LLAMA_ARG_N_CPU_FFN` | `-ncffn, --n-cpu-ffn` | Mantiene en CPU el FFN denso de las **primeras N** capas (modelos densos). | — |

> Los expertos MoE son operaciones de cómputo: sacarlos a RAM obliga a transferirlos
> por PCIe en cada token y **penaliza mucho**. Por eso `llama-hub` los deja en VRAM
> por defecto y el offload es opt-in.

### Caché de expertos (`MOE_CACHE_MIB`), para MoE que no caben

`MOE_CACHE_MIB=N` reserva N MiB de VRAM (repartidos entre GPUs como `--tensor-split`)
para una **caché LRU de pares (capa, experto)**. Requiere que los expertos estén en
RAM (`CPU_MOE` o `N_CPU_MOE`): si ya están en VRAM no hay nada que cachear, y
`llama-hub` avisa si lo configuras así.

Cómo se comporta:

- Cada capa con expertos en RAM tiene un *slot map* en RAM; al copiarlo a la GPU, un
  callback sube **solo los expertos que faltan** y expulsa el menos usado
  recientemente (`head` del LRU). Las subidas contiguas se fusionan.
- **Generación** (batches de ≤32 tokens): es lo único que actualiza el LRU → los
  expertos que más usas se quedan residentes en VRAM.
- **Prompt/prefill** (>32 tokens): la caché pasa a **modo lectura**; lo residente se
  copia GPU→GPU y el resto se sube al buffer de cómputo **sin tocar el LRU**, así que
  un prompt largo no te desaloja los expertos calientes del chat.
- Las capas que ya tienen sus expertos en VRAM (`-ngl`) no pasan por la caché: solo
  actúa sobre tensores `.ffn_*_exps` que estén en RAM.

Dimensionado: `parte densa + KV cache + MOE_CACHE_MIB + buffers ≈ VRAM disponible`.
Ojo, hay dos cifras: la **media** (generación) y el **pico**, que es mayor porque en
los batches grandes (prefill) los expertos usados se copian a VRAM de una pieza
(hasta una capa entera de expertos: ~0,35-0,4 GB con `ubatch` 512).

Ejemplos con tope de 6 GB (GPU de 8 GB), contexto 32k, KV `q8_0` y `ubatch` 512:

| Modelo (GGUF medido) | Denso | KV 32k | Banco | Media | Pico | Slots |
|---|---|---|---|---|---|---|
| Gemma 4 26B A4B (`UD-Q4_K_XL`, QAT) | 1,3 GB | 0,5 GB (SWA) | 3400 MiB | ~5,5 GB | ~5,9 GB | ~1065 de 3840 (28 %) |
| gpt-oss-20b (`MXFP4`) | 1,9 GB | 0,4 GB (SWA) | 3000 MiB | ~5,5 GB | ~5,9 GB | ~237 de 768 (31 %) |
| Qwen3 30B A3B (`UD-Q4_K_XL`) | 1,0 GB | 1,7 GB | 2600 MiB | ~5,4 GB | ~5,7 GB | ~1000 de 6144 (16 %) |

Las cabeceras de esos tres `serve/*.sh` tienen las cuentas completas. Pero ojo con
**dónde** se puede leer el informe real del caché (medido con el build 11580):

- **`llama-server` no lo imprime**: su logger descarta esos mensajes. En el log del
  contenedor tendrás los `print_timing` de cada petición (suficiente para comparar t/s)
  y, si algo va mal, un aviso.
- **`llama cli` / `completion` / `perplexity` / `batched-bench` sí lo vuelcan** (destruyen
  el contexto al terminar), pero **solo con `-lv 4`** (trace). Ejemplo con los mismos
  flags del serve:

```bash
docker run --rm --device /dev/dri \
  --group-add "$(getent group video  | cut -d: -f3)" \
  --group-add "$(getent group render | cut -d: -f3)" \
  -v "$PWD/models:/models:ro" --entrypoint /app/llama \
  ghcr.io/ggml-org/llama.cpp:server-vulkan completion \
  -m /models/<repo>/<fichero>.gguf -ngl 99 -fa 1 -cmoe --moe-cache-mib 2600 \
  -c 4096 -n 64 -no-cnv -lv 4 -p "prueba" 2>&1 | grep -iE 'moe|slots|hit rate'
```

Salida real medida en la RX 6650 XT (granite 4.0 H tiny, `--moe-cache-mib 800`):

```
Vulkan0 MoE cache size =  798.31 MiB for 3487.50 MiB of host experts
20 layers, q6_K:  292 slots (22.8%)
20 layers, q4_K:  292 slots (22.8%)
llama_moe_cache: ubatch <= 8: hits = 10320, misses = 1274, hit rate = 89.01%, uploaded = 1730.74 MiB
llama_moe_cache: ubatch  > 8: hits =   72, misses = 1138, hit rate =  5.95%, uploaded = 1547.40 MiB
```

Que es exactamente el comportamiento buscado: **89 % de acierto en generación**
(`ubatch <= 8`) y **6 % en prefill** (`ubatch > 8`, que va a CPU a propósito y no debe
tocar el LRU). Si el banco no da ni para una capa, en la carga sale el aviso
`MoE cache budget is too small for N layers, they are not cached`.

### `mmap` vs `--load-mode none` con expertos en RAM

Con los expertos en RAM (overrides a CPU) llama.cpp avisa en el log:

```
tensor overrides to CPU are used with mmap enabled - consider using --load-mode none for better performance
```

Con `mmap` (por defecto) el modelo **no se copia a RAM**: sus páginas se leen del
disco la primera vez y quedan en la **caché de páginas** del kernel (en `free` se ve
como `búf/caché`, no como `usado`, y es reclamable).

**Pero en Vulkan/AMD ese `none` no usa RAM normal: coloca los pesos en GTT**, la
memoria visible por la GPU (tope `amdgpu.gttsize`, aquí 15,63 GiB). Medido en este
equipo:

| Modelo | Tamaño | Con `LOAD_MODE=none` |
|---|---|---|
| granite 4.0 H tiny | 3,9 GB | GTT sube 3,88 GiB y carga (26,7 t/s) |
| Qwen3 30B A3B | 17,7 GB | `radv/amdgpu: Not enough memory for command submission` + `device lost`, el contenedor muere |

Y la carga es lenta (~66 MB/s leyendo el fichero en vez de mapearlo, que reutiliza la
caché de páginas). Por eso los `serve/*.sh` de MoE grande dejan el `mmap` por defecto:
el aviso de llama.cpp es correcto, pero aquí no compensa. Si quisieras `none` con un
MoE grande necesitarías subir GTT (`amdgpu.gttsize=24576` al arrancar el kernel) y
aceptar que esa RAM es del driver, no reclamable, y que si se llena el modelo muere con
`device lost` en vez de degradar. En otros backends el buffer host puede ser RAM
normal; mídelo antes de confiar.

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
