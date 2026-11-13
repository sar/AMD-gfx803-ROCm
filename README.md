# gfx803 / Polaris ROCm images (CI build of robertrosenbusch/gfx803_rocm)

Unofficial autobuild of https://github.com/robertrosenbusch/gfx803_rocm (ROCm 6.4.0,
Ubuntu 24.04, rocBLAS + PyTorch recompiled for **gfx803** = RX 570/580/590, Radeon Pro Duo Polaris).
All credit for the Dockerfiles and patches goes to **Robert Rosenbusch**; this repo only adds CI.
Upstream has no LICENSE file — the images bundle ROCm, PyTorch, Ollama, ComfyUI, WhisperX etc.
under their own respective licenses.

## Images
| Target | Image |
|---|---|
| base (rocBLAS gfx803) | `ghcr.io/OWNER/REPO/base:6.4` |
| llama.cpp (HIP) | `ghcr.io/OWNER/REPO/llamacpp:latest` |
| Ollama 0.9.0 + Open-WebUI | `ghcr.io/OWNER/REPO/ollama:0.9.0` |
| PyTorch 2.6 / vision 0.21 / audio 2.6 | `ghcr.io/OWNER/REPO/pytorch:2.6` |
| ComfyUI | `ghcr.io/OWNER/REPO/comfyui:latest` |
| WhisperX | `ghcr.io/OWNER/REPO/whisperx:latest` |

Every target also has a `…:<tag>-YYYYMMDD-<upstream-sha>` pin.

## Build
Actions → **gfx803 ROCm -> GHCR** → Run workflow.
- Start with `targets: base,llamacpp` (or `base,ollama`).
- `pytorch` / `comfyui` / `whisperx` need ~40–50 GB and 2–3 h on 14 cores: **use a self-hosted
  runner** (`runner: my-box`, `cleanup: false`). GitHub-hosted = 4 vCPU / 16 GB / 6 h job cap.
- Packages are created private by default: Package settings → make public + link this repo
  if you want anonymous `docker pull`.

## Host requirements (from upstream README — read it)
- `/dev/kfd` **and** `/dev/dri` present; user in `render` + `video` (reboot after adding).
- PCIe atomics: `sudo grep flags /sys/class/kfd/kfd/topology/nodes/*/io_links/0/properties`
- **No ROCm needed on the host** — everything is inside the container.
- Kernel matters: reported working ≥6.15.8, ≥6.12.21, 6.11, 6.10, 6.9, 6.8, 6.6, 6.2, 5.19;
  **6.13 / 6.14 reported broken** (segfaults in `/dev/kfd`). Check before blaming the image.

## Run
```bash
docker run -it --device=/dev/kfd --device=/dev/dri --group-add=video \
  --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -p 11434:11434 -p 8080:8080 --name ollama ghcr.io/OWNER/REPO/ollama:0.9.0