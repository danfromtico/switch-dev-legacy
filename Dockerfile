# syntax=docker/dockerfile:1
# danfromtico/switch-dev-legacy: devkitA64 with the legacy OpenGL stack, each
# from a pinned revision:
#   libnx                  switchbrew/libnx, newer than devkitPro's release
#   libdrm-nouveau-legacy  devkitPro's libdrm_nouveau with the Wine-NX changes
#   mesa-switch-legacy     Mesa 20.1: EGL/OpenGL/GLES through nvc0
#   libusbhsfs             with the UASP transport and usbntfs' read-only NTFS
#   usbntfs                read-only NTFS for libusbhsfs, in Rust
# and the tools to build them and more: Meson, CMake, Ninja, Rust nightly and
# hactool.

ARG DEVKITA64=devkitpro/devkita64@sha256:1fc388c3a0d34bd2045a6dadcb1020e069d5f876a187fd705de14b4440c00282
FROM ${DEVKITA64}

ARG LIBNX_REVISION=feebd026ca0f5dcc2119f46ad8e0d16ad3dd4973
ARG LIBDRM_NOUVEAU_REPOSITORY=https://github.com/danfromtico/libdrm-nouveau-legacy.git
ARG LIBDRM_NOUVEAU_REVISION=a652eb2e7811d012623ba4904cbb540476e2d7ae
ARG MESA_SWITCH_REPOSITORY=https://github.com/danfromtico/mesa-switch-legacy.git
ARG MESA_SWITCH_REVISION=956633be3105312a434fa277085bc6fc54f94b7d
ARG LIBUSBHSFS_REVISION=625269b7725a6e2a3f2724e8d45b602c1b20ead5
ARG USBNTFS_REVISION=d48589608057cfbb280d42d20c655cb825f12dd4
ARG RUST_TOOLCHAIN=nightly-2026-09-08
ARG MESON_VERSION=1.12.0
ARG MAKO_VERSION=1.4.1
ARG HACTOOL_REVISION=3121a5bf08cd81d3a99719feb2cab3b60767afd5

ENV DEVKITPRO=/opt/devkitpro \
    DEVKITA64=/opt/devkitpro/devkitA64 \
    PATH=/opt/devkitpro/devkitA64/bin:/opt/devkitpro/tools/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- Tools -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-pip python3-setuptools python3-wheel \
        ninja-build pkg-config flex bison curl ca-certificates git cmake make bzip2 \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages meson==${MESON_VERSION} mako==${MAKO_VERSION}
# usbntfs is Rust for a tier-3 target: nightly, core and alloc built from rust-src.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
        --default-toolchain ${RUST_TOOLCHAIN} --component rust-src
RUN git clone https://github.com/SciresM/hactool.git /tmp/hactool \
    && git -C /tmp/hactool checkout -q ${HACTOOL_REVISION} \
    && cp /tmp/hactool/config.mk.template /tmp/hactool/config.mk \
    && make -C /tmp/hactool -j"$(nproc)" \
    && install -m 755 /tmp/hactool/hactool /usr/local/bin/hactool \
    && rm -rf /tmp/hactool

# --- libnx ---------------------------------------------------------------------
# devkitPro's released libnx stays in /opt/devkitpro-release, beside the same
# toolchain, for projects that pin it: Atmosphere builds only against that
# release's API. Build them with DEVKITPRO=/opt/devkitpro-release.
RUN mkdir /opt/devkitpro-release \
    && for entry in /opt/devkitpro/*; do \
           [ "$(basename "$entry")" = libnx ] || ln -s "$entry" /opt/devkitpro-release/; \
       done \
    && cp -a /opt/devkitpro/libnx /opt/devkitpro-release/libnx
RUN git init -q /tmp/libnx \
    && git -C /tmp/libnx fetch -q --depth 1 https://github.com/switchbrew/libnx.git ${LIBNX_REVISION} \
    && git -C /tmp/libnx checkout -q FETCH_HEAD \
    && make -C /tmp/libnx -j"$(nproc)" install \
    && rm -rf /tmp/libnx

# --- libdrm-nouveau-legacy and mesa-switch-legacy ------------------------------
# They replace devkitPro's switch-libdrm_nouveau and switch-mesa, which they
# are built from, and install the same files.
COPY mesa /usr/local/share/switch-dev/mesa
RUN dkp-pacman -Rdd --noconfirm switch-mesa switch-libdrm_nouveau \
    && git clone -q ${LIBDRM_NOUVEAU_REPOSITORY} /tmp/libdrm_nouveau \
    && git -C /tmp/libdrm_nouveau checkout -q ${LIBDRM_NOUVEAU_REVISION} \
    && make -C /tmp/libdrm_nouveau -j"$(nproc)" \
    && make -C /tmp/libdrm_nouveau install \
    && install -Dm644 /tmp/libdrm_nouveau/README.md \
        /opt/devkitpro/portlibs/switch/share/licenses/libdrm-nouveau-legacy/README.md \
    && rm -rf /tmp/libdrm_nouveau
RUN git clone -q ${MESA_SWITCH_REPOSITORY} /tmp/mesa-switch \
    && git -C /tmp/mesa-switch checkout -q ${MESA_SWITCH_REVISION} \
    && cd /tmp/mesa-switch && bash /usr/local/share/switch-dev/mesa/build.sh \
    && rm -rf /tmp/mesa-switch

# --- libusbhsfs with usbntfs --------------------------------------------------
# libusbhsfs is built with devkitA64 with x18 left alone, which Wine keeps its
# thread data in, with the UASP transport and read-only NTFS through usbntfs:
# libusbntfs.a (Rust, no_std) beside libusbhsfs.a; link -lusbhsfs -lusbntfs.
COPY cmake/switch.cmake /opt/devkitpro/cmake/switch-dev.cmake
COPY libusbhsfs /usr/local/share/switch-dev/libusbhsfs
RUN git init -q /tmp/libusbhsfs \
    && git -C /tmp/libusbhsfs fetch -q --depth 1 https://github.com/ITotalJustice/libusbhsfs.git ${LIBUSBHSFS_REVISION} \
    && git -C /tmp/libusbhsfs checkout -q FETCH_HEAD \
    && for patch in /usr/local/share/switch-dev/libusbhsfs/*.patch; do \
           tr -d '\r' < "$patch" | git -C /tmp/libusbhsfs apply - || exit 1; \
       done \
    && git init -q /tmp/usbntfs \
    && git -C /tmp/usbntfs fetch -q --depth 1 https://github.com/danfromtico/usbntfs.git ${USBNTFS_REVISION} \
    && git -C /tmp/usbntfs checkout -q FETCH_HEAD \
    && python3 /usr/local/share/switch-dev/libusbhsfs/usbntfs.py /tmp/libusbhsfs /tmp/usbntfs \
    && (cd /tmp/usbntfs && RUSTFLAGS="-C target-cpu=cortex-a57" cargo build --locked --release \
        --target aarch64-nintendo-switch-freestanding -Z build-std=core,alloc -Z build-std-features=) \
    && install -m644 /tmp/usbntfs/target/aarch64-nintendo-switch-freestanding/release/libusbntfs.a \
        /opt/devkitpro/portlibs/switch/lib/libusbntfs.a \
    && install -m644 /tmp/usbntfs/include/usbntfs.h /opt/devkitpro/portlibs/switch/include/usbntfs.h \
    && install -Dm644 /tmp/usbntfs/THIRD_PARTY_NOTICES.md \
        /opt/devkitpro/portlibs/switch/share/licenses/usbntfs/THIRD_PARTY_NOTICES.md \
    && cmake -S /usr/local/share/switch-dev/libusbhsfs -B /tmp/libusbhsfs-build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=/opt/devkitpro/cmake/switch-dev.cmake -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/devkitpro/portlibs/switch -DUSBHSFS_SOURCE=/tmp/libusbhsfs \
        -DUSBNTFS_SOURCE=/tmp/usbntfs \
    && ninja -C /tmp/libusbhsfs-build install \
    && rm -rf /tmp/libusbhsfs /tmp/libusbhsfs-build /tmp/usbntfs /root/.cargo/registry

# What this image holds, for a build to record.
RUN printf '{\n  "devkita64": "%s",\n  "libnx": "%s",\n  "libdrm_nouveau_legacy": "%s",\n  "mesa_switch_legacy": "%s",\n  "libusbhsfs": "%s",\n  "usbntfs": "%s",\n  "rust": "%s"\n}\n' \
        "$(dkp-pacman -Q devkitA64 | cut -d' ' -f2)" ${LIBNX_REVISION} ${LIBDRM_NOUVEAU_REVISION} \
        ${MESA_SWITCH_REVISION} ${LIBUSBHSFS_REVISION} ${USBNTFS_REVISION} ${RUST_TOOLCHAIN} \
        > /opt/devkitpro/portlibs/switch/share/switch-dev.json

LABEL org.opencontainers.image.source=https://github.com/danfromtico/switch-dev-legacy \
      org.opencontainers.image.description="devkitA64 with libnx, libdrm-nouveau-legacy, mesa-switch-legacy, libusbhsfs and usbntfs for Horizon" \
      dev.tico.libnx=${LIBNX_REVISION} \
      dev.tico.libdrm-nouveau-legacy=${LIBDRM_NOUVEAU_REVISION} \
      dev.tico.mesa-switch-legacy=${MESA_SWITCH_REVISION} \
      dev.tico.libusbhsfs=${LIBUSBHSFS_REVISION} \
      dev.tico.usbntfs=${USBNTFS_REVISION} \
      dev.tico.rust=${RUST_TOOLCHAIN}
WORKDIR /work
