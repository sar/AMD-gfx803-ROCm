# syntax=docker/dockerfile:1
# gfx803/Polaris ROCm 6.4 + llama.cpp (HIP) + C++/Rust/Bun dev toolchain.
# Build steps mirrored from https://github.com/robertrosenbusch/gfx803_rocm
#   Dockerfile_rocm64_base + Dockerfile_rocm64_llamacpp
FROM rocm/dev-ubuntu-24.04:6.4-complete

ARG MAX_JOBS=4
ARG UPSTREAM_REF=main
ARG ROCBLAS_REF=rocm-6.4.0
ARG LLAMACPP_REF=""

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    MAX_JOBS=${MAX_JOBS} \
    HSA_OVERRIDE_GFX_VERSION=8.0.3 \
    PYTORCH_ROCM_ARCH=gfx803 \
    ROCM_ARCH=gfx803 \
    ROC_ENABLE_PRE_VEGA=1 \
    TORCH_BLAS_PREFER_HIPBLASLT=0 \
    USE_CUDA=0 USE_ROCM=1 USE_NINJA=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    BUN_INSTALL=/usr/local/bun \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    CCACHE_DIR=/ccache

ENV PATH="/usr/lib/ccache:${BUN_INSTALL}/bin:${CARGO_HOME}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl wget unzip pkg-config libssl-dev ca-certificates \
    cmake ninja-build python3 python3-dev python3-venv python3-pip virtualenv \
    rocm-cmake libgomp1 libomp-dev libopenblas-dev google-perftools \
    ccache autoconf automake libtool \
    gdb valgrind lcov cppcheck clang-format clang-tidy \
    nmap htop lsof strace tcpdump iputils-ping dnsutils net-tools \
    ripgrep fd-find tmux screen vim nano zsh \
    jq yq \
    nlohmann-json3-dev libfmt-dev libspdlog-dev libboost-all-dev \
    libprotobuf-dev protobuf-compiler libgrpc++-dev libgflags-dev \
    libgoogle-glog-dev libgtest-dev libgmock-dev libbenchmark-dev \
    libcurl4-openssl-dev zlib1g-dev libbz2-dev liblzma-dev libffi-dev libsqlite3-dev \
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
    libsdl2-dev libglew-dev libglfw3-dev libvulkan-dev vulkan-tools \
    && rm -rf /var/lib/apt/lists/*

# Go yq replaces the apt python jq-wrapper; fd-find installs as 'fdfind'
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && mkdir -p /ccache && chmod 777 /ccache \
    && yq --version

# Bun
RUN set -o pipefail; \
    curl -fsSL https://bun.sh/install | bash \
    && ln -sf "${BUN_INSTALL}/bin/bun" "${BUN_INSTALL}/bin/bunx" \
    && bun --version

# Rust
RUN set -o pipefail; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --component rustfmt --component clippy \
    && rustc --version && cargo --version

# Provenance: upstream Dockerfiles + exact commit
RUN git clone https://github.com/robertrosenbusch/gfx803_rocm.git /opt/gfx803_rocm \
    && git -C /opt/gfx803_rocm checkout --detach "${UPSTREAM_REF}" \
    && git -C /opt/gfx803_rocm rev-parse HEAD > /opt/gfx803-upstream-commit \
    && rm -rf /opt/gfx803_rocm/.git && cat /opt/gfx803-upstream-commit

RUN wget -q https://github.com/Umio-Yasuno/amdgpu_top/releases/download/v0.10.4/amdgpu-top_0.10.4-1_amd64.deb -O /tmp/amdgpu-top.deb \
    && dpkg -i --force-depends /tmp/amdgpu-top.deb && rm -f /tmp/amdgpu-top.deb

# rocBLAS rebuilt for gfx803
RUN git clone --depth 1 -b "${ROCBLAS_REF}" https://github.com/ROCm/rocBLAS.git /rocblas \
    && cd /rocblas \
    && ./install.sh -ida "${ROCM_ARCH}" -j "${MAX_JOBS}" \
    && ls /opt/rocm/lib/rocblas/library/ | grep -c gfx803 \
    && rm -rf /rocblas/build

# llama.cpp with HIP for gfx803
RUN set -euo pipefail; \
    git clone https://github.com/ggml-org/llama.cpp /llama.cpp; \
    cd /llama.cpp; \
    if [ -n "${LLAMACPP_REF}" ]; then git checkout --detach "${LLAMACPP_REF}"; fi; \
    git rev-parse HEAD > /llama.cpp-commit; \
    HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
      cmake -S . -B build -DGGML_HIP=ON -DLLAMA_CURL=OFF -DAMDGPU_TARGETS=gfx803 -DCMAKE_BUILD_TYPE=Release; \
    cmake --build build --config Release -- -j "${MAX_JOBS}"; \
    rm -rf /llama.cpp/.git; \
    ccache -s || true; ccache -C || true

EXPOSE 8080
CMD ["/bin/bash"]