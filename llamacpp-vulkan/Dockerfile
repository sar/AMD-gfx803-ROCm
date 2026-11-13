# syntax=docker/dockerfile:1
# llama.cpp Vulkan (RADV) + memtest_vulkan + full dev toolchain + AMD monitoring.
# Everything source-wise lives in /workspace so the image can rebuild itself offline.
FROM ubuntu:26.04

ARG MAX_JOBS=4
ARG LLAMACPP_REF=""
ARG MEMTEST_REF=main
ARG AMDGPU_TOP_VERSION=0.11.5
ARG VULKAN_DEBUG=OFF
ARG WITH_MESA_SRC=1
ARG OFFLINE_DEBS=0

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    MAX_JOBS=${MAX_JOBS} \
    GOTOOLCHAIN=auto \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    BUN_INSTALL=/usr/local/bun \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CCACHE_DIR=/ccache

ENV PATH="/usr/lib/ccache:${BUN_INSTALL}/bin:${CARGO_HOME}/bin:${PATH}"

# Vulkan build deps per llama.cpp docs/build.md + ggml-vulkan/CMakeLists.txt:
#   find_package(Vulkan COMPONENTS glslc REQUIRED) -> libvulkan-dev + glslc
#   find_package(SPIRV-Headers CONFIG REQUIRED)    -> spirv-headers (NOT pulled by libvulkan-dev)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl wget unzip pkg-config libssl-dev ca-certificates \
    cmake ninja-build python3 python3-dev python3-venv python3-pip \
    libvulkan-dev glslc spirv-headers spirv-tools mesa-vulkan-drivers libvulkan1 vulkan-tools \
    libdrm-amdgpu1 libdrm-dev \
    amd-smi rocm-smi radeontop lm-sensors \
    libgomp1 libomp-dev libopenblas-dev libtcmalloc-minimal4 \
    ccache autoconf automake libtool meson \
    gdb valgrind lcov cppcheck clang-format clang-tidy \
    nmap htop lsof strace tcpdump iputils-ping dnsutils net-tools \
    ripgrep fd-find tmux screen vim nano zsh \
    jq yq \
    nlohmann-json3-dev libfmt-dev libspdlog-dev libboost-all-dev \
    libprotobuf-dev protobuf-compiler libgrpc++-dev libgflags-dev \
    libgoogle-glog-dev libgtest-dev libgmock-dev libbenchmark-dev \
    libcurl4-openssl-dev zlib1g-dev libbz2-dev liblzma-dev libffi-dev libsqlite3-dev \
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
    libsdl2-dev libglew-dev libglfw3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && mkdir -p /ccache /workspace && chmod 777 /ccache \
    && yq --version

RUN set -o pipefail; \
    curl -fsSL https://bun.sh/install | bash \
    && ln -sf "${BUN_INSTALL}/bin/bun" "${BUN_INSTALL}/bin/bunx" && bun --version

# Rust >= 1.89 required by memtest_vulkan (edition 2024)
RUN set -o pipefail; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --component rustfmt --component clippy \
    && rustc --version && cargo --version

RUN apt-get update \
    && wget -q "https://github.com/Umio-Yasuno/amdgpu_top/releases/download/v${AMDGPU_TOP_VERSION}/amdgpu-top_${AMDGPU_TOP_VERSION}-1_amd64.deb" -O /tmp/amdgpu-top.deb \
    && dpkg -i --force-depends /tmp/amdgpu-top.deb \
    && rm -f /tmp/amdgpu-top.deb && rm -rf /var/lib/apt/lists/*

# ---------- /workspace/vulkan : upstream sources for the whole Vulkan stack ----------
RUN set -euo pipefail; mkdir -p /workspace/vulkan; cd /workspace/vulkan; \
    for r in \
      https://github.com/KhronosGroup/Vulkan-Headers.git \
      https://github.com/KhronosGroup/Vulkan-Loader.git \
      https://github.com/KhronosGroup/SPIRV-Headers.git \
      https://github.com/KhronosGroup/SPIRV-Tools.git \
      https://github.com/KhronosGroup/glslang.git \
      https://github.com/google/shaderc.git ; do \
      git clone --depth 1 "$r"; \
    done; \
    if [ "${WITH_MESA_SRC}" = "1" ]; then git clone --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git; fi; \
    for d in */; do git -C "$d" rev-parse HEAD > "$d/CLONED_COMMIT"; done; \
    du -sh /workspace/vulkan

# ---------- /workspace/llama.cpp : source kept for offline rebuild ----------
RUN set -euo pipefail; \
    git clone https://github.com/ggml-org/llama.cpp /workspace/llama.cpp; \
    cd /workspace/llama.cpp; \
    if [ -n "${LLAMACPP_REF}" ]; then git checkout --detach "${LLAMACPP_REF}"; fi; \
    git rev-parse HEAD > /workspace/llama.cpp/CLONED_COMMIT; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_VULKAN=ON \
      -DLLAMA_CURL=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DGGML_NATIVE=OFF \
      -DGGML_VULKAN_VALIDATE=${VULKAN_DEBUG} \
      -DGGML_VULKAN_DEBUG=${VULKAN_DEBUG} \
      -DGGML_VULKAN_MEMORY_DEBUG=${VULKAN_DEBUG} \
      -DGGML_VULKAN_SHADER_DEBUG_INFO=${VULKAN_DEBUG}; \
    cmake --build build --config Release -- -j "${MAX_JOBS}"; \
    install -m 0755 build/bin/llama-cli build/bin/llama-server build/bin/llama-bench /usr/local/bin/; \
    rm -rf /workspace/llama.cpp/.git

# ---------- /workspace/vulkan-memtest : source + vendored crates (offline) ----------
RUN set -euo pipefail; \
    git clone https://github.com/GpuZelenograd/memtest_vulkan.git /workspace/vulkan-memtest; \
    cd /workspace/vulkan-memtest; \
    if [ "${MEMTEST_REF}" != "main" ]; then git checkout --detach "${MEMTEST_REF}"; fi; \
    git rev-parse HEAD > CLONED_COMMIT; \
    cargo vendor --locked /workspace/vulkan-memtest/vendor > /tmp/vendor-config.toml; \
    cat /tmp/vendor-config.toml >> .cargo/config.toml; \
    cargo build --release --locked --offline; \
    install -m 0755 target/release/memtest_vulkan /usr/local/bin/memtest_vulkan; \
    rm -rf .git target/release/build target/release/deps target/release/incremental; \
    du -sh /workspace/vulkan-memtest

# ---------- optional: .deb cache for offline apt reinstall ----------
RUN set -euo pipefail; \
    if [ "${OFFLINE_DEBS}" = "1" ]; then \
      mkdir -p /workspace/debs; apt-get update; \
      apt-get -o Dir::Cache::archives=/workspace/debs --download-only install -y \
        mesa-vulkan-drivers libvulkan1 libvulkan-dev glslc spirv-headers spirv-tools \
        cmake ninja-build build-essential pkg-config libcurl4-openssl-dev libssl-dev; \
      rm -rf /var/lib/apt/lists/*; \
    fi

COPY <<'EOF' /workspace/README.md
# /workspace — offline rebuild kit

Everything here is source. The toolchain (gcc, cmake, ninja, glslc, spirv-headers,
cargo/rustc, ccache) is already installed in the image, so NO network is needed to rebuild.

## llama.cpp (Vulkan/RADV)
    cd /workspace/llama.cpp
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DGGML_VULKAN=ON -DLLAMA_CURL=ON -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF
    cmake --build build -- -j"$(nproc)"
    install -m0755 build/bin/llama-{cli,server,bench} /usr/local/bin/
Add -DGGML_AVX2=OFF if the host CPU is pre-Haswell.

## memtest_vulkan  (crates vendored, incl. the `mortal` git dependency)
    cd /workspace/vulkan-memtest
    cargo build --release --locked --offline
    install -m0755 target/release/memtest_vulkan /usr/local/bin/
Shaders are WGSL -> SPIR-V via the naga proc-macro; no glslc needed for this one.

## Vulkan stack sources (/workspace/vulkan)
Vulkan-Headers, Vulkan-Loader, SPIRV-Headers, SPIRV-Tools, glslang, shaderc, mesa.
Each dir has CLONED_COMMIT with the exact upstream SHA.
- headers/loader/spirv/glslang build with plain cmake.
- shaderc normally populates third_party via utils/git-sync-deps (needs network);
  the sibling clones here are provided so you can symlink them instead.
- mesa (RADV) needs extra dev deps (llvm-dev, libdrm-dev, meson, wayland-protocols,
  libxcb*-dev, bison, flex ...) that are NOT all installed here.

## Offline apt (only if built with --build-arg OFFLINE_DEBS=1)
    dpkg -i /workspace/debs/*.deb    # or: apt-get install --no-download <pkg>
EOF

COPY <<'EOF' /workspace/build-all.sh
#!/bin/bash
set -euo pipefail
J="$(nproc)"
cd /workspace/llama.cpp
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGGML_VULKAN=ON -DLLAMA_CURL=ON -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF
cmake --build build -- -j"$J"
install -m0755 build/bin/llama-cli build/bin/llama-server build/bin/llama-bench /usr/local/bin/
cd /workspace/vulkan-memtest
cargo build --release --locked --offline
install -m0755 target/release/memtest_vulkan /usr/local/bin/
echo "OK: llama.cpp + memtest_vulkan rebuilt offline"
EOF
RUN chmod +x /workspace/build-all.sh

# Polaris: keep tensors in VRAM instead of silently spilling to GTT (Mesa >= 25.2).
# Pinning the RADV ICD also keeps llvmpipe out of memtest_vulkan's device menu.
ENV RADV_PERFTEST=nogttspill \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json

EXPOSE 8080
WORKDIR /workspace
CMD ["/bin/bash"]