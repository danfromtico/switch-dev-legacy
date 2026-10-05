# switch-dev-legacy

A Docker image for building Horizon (Nintendo Switch) homebrew against the
legacy OpenGL stack: devkitA64 with Mesa 20.1's nvc0 over libdrm_nouveau, as
devkitPro ships it but with the Wine-NX changes, a newer libnx, and USB drives
with UASP and read-only NTFS. Each comes from a pinned revision.

It is the legacy counterpart of
[autorunhq/switch-dev](https://github.com/autorunhq/switch-dev), which carries
Mesa 26 (nvc0, Zink and NVK Vulkan).

| In portlibs | Revision | |
|---|---|---|
| [libnx](https://github.com/switchbrew/libnx) | `feebd026` | newer than devkitPro's 4.12.0 release |
| [libdrm-nouveau-legacy](https://github.com/danfromtico/libdrm-nouveau-legacy) | `a652eb2e` | devkitPro's libdrm_nouveau 1.0.1 with the Wine-NX changes: buffer object reuse, pinned application memory. Replaces `switch-libdrm_nouveau`. |
| [mesa-switch-legacy](https://github.com/danfromtico/mesa-switch-legacy) | `956633be` | Mesa 20.1 with devkitPro's Switch port and the Wine-NX changes: EGL, OpenGL and GLES through nvc0, GPU texture uploads, `GL_AMD_pinned_memory`, 3D-engine copies. Replaces `switch-mesa`, built the same way. |
| [libusbhsfs](https://github.com/ITotalJustice/libusbhsfs) | `625269b7` | with the UASP transport in `libusbhsfs/`; FAT and exFAT, and NTFS read-only through usbntfs: `libusbhsfs.a` |
| [usbntfs](https://github.com/danfromtico/usbntfs) | `d4858960` | read-only NTFS without GPL code, in `no_std` Rust: `libusbntfs.a` |

There is no Vulkan driver: Mesa 20.1 has none for this GPU.

Tools: CMake, Ninja, Meson 1.12, Rust `nightly-2026-09-08` with rust-src,
and hactool 1.4.0.

`/opt/devkitpro-release` is the same toolchain with devkitPro's released
libnx (4.12.0), for projects pinned to it such as Atmosphère: build them with
`DEVKITPRO=/opt/devkitpro-release`.

`/opt/devkitpro/cmake/switch-dev.cmake` is the CMake toolchain libusbhsfs is
built with. It leaves x18 alone, as Wine on Horizon needs.
`/opt/devkitpro/portlibs/switch/share/switch-dev.json` lists the revisions,
and so do the image's labels.

## Use

```sh
docker run --rm -v "$PWD:/work" ghcr.io/danfromtico/switch-dev-legacy make
```

Link OpenGL as with devkitPro's Mesa: `-lEGL -lglapi -ldrm_nouveau` (and
`-lGLESv2` or `-lGLESv1_CM` for direct GLES calls), or `find_package(OpenGL)`
in CMake. Link USB drives with `-lusbhsfs -lusbntfs`.

The image is built for `linux/amd64` and `linux/arm64`, each natively on its
own runner.

## Build

```sh
docker build --platform linux/arm64 -t ghcr.io/danfromtico/switch-dev-legacy .
```

To change a revision, edit its `ARG` in the `Dockerfile`.

Pushing a tag named for the day it is cut, such as `2026.10.05`, builds the
image on GitHub's amd64 and arm64 runners and publishes it as
`ghcr.io/danfromtico/switch-dev-legacy:2026.10.05` and `:latest`
(`.github/workflows/publish.yml`).

## Licenses

The Dockerfile and build scripts are MIT. What the image builds keeps its own
license, installed under `portlibs/switch/share/licenses`:
- mesa-switch-legacy and libdrm-nouveau-legacy are MIT.
- libusbhsfs is ISC as built here (no NTFS-3G or ext4).
- usbntfs is MIT OR Apache-2.0.
