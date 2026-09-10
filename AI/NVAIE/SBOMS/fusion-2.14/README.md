# NVAIE SBOMs — IBM Storage Fusion 2.14

One SBOM per NVIDIA NIM container image shipped with Storage Fusion 2.14.
See [`../../README.md`](../../README.md) for programme context.


## `sbom-cosmos-reason2-8b-1.7.0-amd64.json`

**Cosmos-Reason2 8B (v1.7.0) — multimodal reasoning NIM** (Ubuntu 22.04, 625 components)

- **Image:** `nvstaging/nim/cosmos-reason2-8b:1.7.0.rc1-48244744`
- **Model:** `nvidia/cosmos-reason2-8b`
- **NIM type:** `multimodal`
- **NSPECT (image):** `NSPECT-HFIK-RMS9` · **NSPECT (model):** `NSPECT-4XVH-14YQ`


## `sbom-gpt-oss-120b-2.0.10-amd64.json`

**GPT-OSS 120B (v2.0.10) — large open-source LLM NIM** (vLLM v0.26.0 / Ubuntu 24.04, 675 components)

- **Image:** `nvstaging/nim/gpt-oss-120b:2.0.10-595b92ec608a21d1`
- **Model:** `openai/gpt-oss-120b`
- **NIM type:** `llm`
- **Base runtime:** vLLM `v0.26.0` (commit `ffd46bfa`)
- **NSPECT (image):** `NSPECT-OACO-UK0E` · **NSPECT (model):** `NSPECT-EEZS-7JBM`


## `sbom-llama-nemotron-embed-1b-v2-1-amd64.json`

**Llama-Nemotron Embed 1B v2 (v1.13.0) — text embedding NIM** (Ubuntu 24.04, 335 components)

- **Image:** `nvcr.io/nvstaging/nim/llama-nemotron-embed-1b-v2:1.13.0-5e5e5bfe386f1a12`
  - **Digest:** `sha256:34fc9b2be19fefaf56b56461730c08ac6a153558250b735be0ed603a06aee267`
- **Model:** `nvidia/llama-nemotron-embed-1b-v2`
- **NIM type:** `embedding`
- **Base image:** `nvcr.io/nvstaging/nim/nemo-retriever-embedding:1.13.0`
- **NSPECT (image):** `NSPECT-A2V9-7M6B` · **NSPECT (model):** `NSPECT-31UJ-S8X4`


## `sbom-llama-nemotron-rerank-1b-v2-1.1-amd64.json`

**Llama-Nemotron Rerank 1B v2 (v1.10.0) — passage re-ranking NIM** (Ubuntu 24.04, 316 components)

- **Image:** `nvcr.io/nvstaging/nim/llama-nemotron-rerank-1b-v2:1.10.0-229c43b26faa3082`
  - **Digest:** `sha256:31068f08a6119b0df17fabaa14677b12e903df195de5e4f3f0ee7f0670cb2575`
- **Model:** `nvidia/llama-nemotron-rerank-1b-v2`
- **NIM type:** `ranking`
- **Base image:** `nvcr.io/nvstaging/nim/reranking-triton:1.10.0`
- **NSPECT (image):** `NSPECT-8TPD-PH99` · **NSPECT (model):** `NSPECT-VZY2-WM4U`


## `sbom-nemotron-3-nano-latest-amd64.json`

**Nemotron-3 Nano (v2.0.10) — compact general-purpose LLM NIM** (vLLM v0.26.0 / Ubuntu 24.04, 675 components)

- **Image:** `nvstaging/nim/nemotron-nano-3:2.0.10-0f4acb26f9f8e978`
- **Model:** `nvidia/nemotron-3-nano`
- **NIM type:** `llm`
- **Base runtime:** vLLM `v0.26.0` (commit `ffd46bfa`)
- **NSPECT (image):** `NSPECT-BEI3-H0NR` · **NSPECT (model):** `NSPECT-XTN3-827R`


## `sbom-nemotron-3-super-120b-a12b-3.0.0-amd64.json`

**Nemotron-3 Super 120B A12B (v3.0.0) — Dynamo-accelerated MoE LLM NIM** (vLLM v0.26.0 / Ubuntu 24.04, 677 components)

- **Image:** `nvstaging/nim/nemotron-3-super-dynamo:3.0.0-611263a66e61ebe4`
- **Model:** `nvidia/nemotron-3-super-120b-a12b`
- **NIM type:** `llm`
- **Base runtime:** vLLM `v0.26.0` (commit `ffd46bfa`)
- **NSPECT (image):** `NSPECT-YN18-TKF1` · **NSPECT (model):** `NSPECT-Q8Q0-SB01`


## `sbom-nemotron-graphic-elements-v1-1.8.0-amd64.json`

**Nemotron Graphic Elements v1 (v1.8.0) — graphic/figure object-detection NIM** (Ubuntu 24.04, 343 components)

- **Image:** `nvcr.io/nvstaging/nim/nemotron-graphic-elements-v1:1.8.0-7bbec7bb82f9b482`
  - **Digest:** `sha256:8e537ba043c44c55f1f5e2fd019f190d4f190ac75df28e332228f2b637b0d5c3`
- **Model:** `nvidia/nemotron-graphic-elements-v1`
- **NIM type:** `object-detection`
- **Base image:** `nvcr.io/nvstaging/nim/object-detection:1.8.0`
- **NSPECT (image):** `NSPECT-7OBP-T77C` · **NSPECT (model):** `NSPECT-3A0Q-P34G`


## `sbom-nemotron-nano-12b-v2-vl-1.6.0-amd64.json`

**Nemotron Nano 12B v2 VL (v1.6.0) — vision-language multimodal LLM NIM** (Ubuntu 24.04, 683 components)

- **Image:** `nvcr.io/nvstaging/nim/nemotron-nano-12b-v2-vl:1.6.0-42611854`
  - **Digest:** `sha256:f926731b1687fbd5a2dd48e5516331745c6d0b8fb6f653fd85a561fd88d15eff`
- **Model:** `nvidia/nemotron-nano-12b-v2-vl`
- **NIM type:** `llm` (vision-language)


## `sbom-nemotron-ocr-v1-1.3.0-amd64.json`

**Nemotron OCR v1 (v1.3.0) — optical character recognition NIM** (Ubuntu 24.04, 349 components)

- **Image:** `nvcr.io/nvstaging/nim/nemotron-ocr-v1:1.3.0-cd72178f1c0c3f41`
  - **Digest:** `sha256:4ed517af381b88c4d18d5f7ed1686fb058cdef0a8924100ba681975e1284f6be`
- **Model:** `nvidia/nemoretriever-ocr-v1`
- **NIM type:** `ocr`


## `sbom-nemotron-page-elements-v3-1.8-amd64.json`

**Nemotron Page Elements v3 (v1.8.0) — page-layout object-detection NIM** (Ubuntu 24.04, 343 components)

- **Image:** `nvcr.io/nvstaging/nim/nemotron-page-elements-v3:1.8.0-92487deb5f7fc598`
  - **Digest:** `sha256:ff2fbf6bca4c0a600e9109f8c1ecee467082082d0733487bc2bd3ca4bd4a259d`
- **Model:** `nvidia/nemotron-page-elements-v3`
- **NIM type:** `object-detection`
- **Base image:** `nvcr.io/nvstaging/nim/object-detection:1.8.0`


## `sbom-nemotron-table-structure-v1-1-amd64.json`

**Nemotron Table Structure v1 (v1.8.0) — table layout object-detection NIM** (Ubuntu 24.04, 343 components)

- **Image:** `nvcr.io/nvstaging/nim/nemotron-table-structure-v1:1.8.0-af019f6da2f1e36d`
  - **Digest:** `sha256:d79617ab07eb18211ec0c4cb81df173cecab919a9ad09aa81c7a4e7c132e891c`
- **Model:** `nvidia/nemotron-table-structure-v1`
- **NIM type:** `object-detection`
- **Base image:** `nvcr.io/nvstaging/nim/object-detection:1.8.0`
