#!/bin/bash
# Build mesa-switch-legacy (Mesa 20.1 with devkitPro's Switch port: EGL,
# OpenGL and GLES through Gallium nvc0 over libdrm_nouveau) from the checkout
# in the current directory, and install it into portlibs as devkitPro's
# switch-mesa package does.
set -euo pipefail
portlibs=/opt/devkitpro/portlibs/switch

# devkitA64's newlib now declares timespec_get, which Mesa 20.1's C11 threads
# header defines as static.
git apply /usr/local/share/switch-dev/mesa/timespec_get.patch

# The same configuration as switch-mesa's PKGBUILD: the switch platform, nvc0
# and static libraries are the port's defaults in meson.build.
/opt/devkitpro/meson-cross.sh switch /tmp/mesa-crossfile.txt /tmp/mesa-build -Db_ndebug=true
ninja -C /tmp/mesa-build
meson install -C /tmp/mesa-build --no-rebuild

# What switch-mesa's package() adds: EGL pulls libdrm_nouveau in, and CMake's
# find_package(OpenGL) finds EGL, glapi and libdrm_nouveau.
sed -i 's,-lEGL,-lEGL -ldrm_nouveau,' $portlibs/lib/pkgconfig/egl.pc
install -Dm644 /usr/local/share/switch-dev/mesa/OpenGLConfig.cmake \
    $portlibs/lib/cmake/OpenGL/OpenGLConfig.cmake
mkdir -p $portlibs/share/licenses/mesa-switch-legacy
cp docs/license.html $portlibs/share/licenses/mesa-switch-legacy/
rm -rf /tmp/mesa-build /tmp/mesa-crossfile.txt
