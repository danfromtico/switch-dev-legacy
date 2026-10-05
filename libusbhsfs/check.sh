#!/bin/sh
# Host tests of the UASP patch series: the pinned libusbhsfs, patched, in a
# temporary checkout. Needs git, python3 and cc.
set -eu
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
revision="$(sed -n 's/^ARG LIBUSBHSFS_REVISION=//p' "$here/../Dockerfile")"
checkout="$(mktemp -d "${TMPDIR:-/tmp}/libusbhsfs.XXXXXX")"
trap 'rm -rf "$checkout"' EXIT HUP INT TERM
git -C "$checkout" init -q
git -C "$checkout" fetch -q --depth 1 https://github.com/ITotalJustice/libusbhsfs.git "$revision"
git -C "$checkout" checkout -q FETCH_HEAD
for patch in "$here"/*.patch; do
    tr -d '\r' < "$patch" | git -C "$checkout" apply -
done
export USBHSFS_SOURCE="$checkout"
python3 "$here/tests/check_usb_transfers.py"
python3 "$here/tests/check_usb_storage.py"
