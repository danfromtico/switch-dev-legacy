#!/usr/bin/env python3
"""Adds usbntfs' read-only NTFS to the libusbhsfs fork built here.

usbntfs (https://github.com/danfromtico/usbntfs) ships the same change for
DarkMatterCore's libusbhsfs v0.2.9, where NTFS hangs off GPL_BUILD; the fork
guards each filesystem on its own (USBHSFS_NTFS, USBHSFS_EXT4), and the UASP
patches add a teardown check per filesystem. So the usbntfs blocks here follow
each USBHSFS_NTFS block, guarded by USBNTFS_BUILD, which CMakeLists.txt sets.

    usbntfs.py <libusbhsfs checkout> <usbntfs checkout>
"""
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1])
usbntfs = pathlib.Path(sys.argv[2])


def edit(rel, pairs):
    path = root / rel
    text = path.read_text()
    for old, new in pairs:
        if text.count(old) != 1:
            sys.exit(f"{rel}: anchor not found once: {old[:70]!r}")
        text = text.replace(old, old + new)
    path.write_text(text)


# The devoptab includes ../usbhsfs_manager.h, so it lives beside the sources.
shutil.copytree(usbntfs / "libusbhsfs" / "source" / "usbntfs", root / "source" / "usbntfs",
                dirs_exist_ok=True)

edit("source/usbhsfs_drive.h", [
("""#ifdef USBHSFS_NTFS
#include "ntfs-3g/ntfs.h"
#endif
""",
"""#ifdef USBNTFS_BUILD
#include "usbntfs/usbntfs_dev.h"
#endif
"""),
("""#ifdef USBHSFS_NTFS
    ntfs_vd *ntfs;      ///< Pointer to a dynamically allocated ntfs_vd object. Only used if fs_type == UsbHsFsFileSystemType_NTFS.
#endif
""",
"""#ifdef USBNTFS_BUILD
    usbntfs_vd *usbntfs;    ///< Read-only NTFS volume. Only used if fs_type == UsbHsFsFileSystemType_NTFS.
#endif
"""),
("""            case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
                fs_valid = (fs_ctx->ntfs != NULL);
                break;
#endif
""",
"""#ifdef USBNTFS_BUILD
            case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
                fs_valid = (fs_ctx->usbntfs != NULL);
                break;
#endif
"""),
])

edit("source/usbhsfs_manager.c", [(
"""        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
            device->fs_type = UsbHsFsDeviceFileSystemType_NTFS;
            break;
#endif
""",
"""#ifdef USBNTFS_BUILD
        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
            device->fs_type = UsbHsFsDeviceFileSystemType_NTFS;
            device->write_protect = true;   /* mounted read-only */
            break;
#endif
""")])

edit("source/usbhsfs_mount.c", [
("""static bool usbHsFsMountRegisterExtVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx, u64 block_addr, u64 block_count);
static void usbHsFsMountUnregisterExtVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx);
#endif
""",
"""#ifdef USBNTFS_BUILD
static bool usbHsFsMountRegisterUsbNtfsVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx, u64 block_addr, u64 block_count);
static void usbHsFsMountUnregisterUsbNtfsVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx);
#endif
"""),
# The UASP patches' teardown check.
("""        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
            if (!fs_ctx->ntfs) return;
            break;
#endif
""",
"""#ifdef USBNTFS_BUILD
        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:
            if (!fs_ctx->usbntfs) return;
            break;
#endif
"""),
("""        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS. */
            usbHsFsMountUnregisterNtfsVolume(fs_ctx);
            break;
#endif
""",
"""#ifdef USBNTFS_BUILD
        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS, read-only. */
            usbHsFsMountUnregisterUsbNtfsVolume(fs_ctx);
            break;
#endif
"""),
("""        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS. */
            ret = usbHsFsMountRegisterNtfsVolume(fs_ctx, block, block_addr);
            break;
#endif
""",
"""#ifdef USBNTFS_BUILD
        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS, read-only. */
            ret = usbHsFsMountRegisterUsbNtfsVolume(fs_ctx, block_addr, block_count);
            break;
#endif
"""),
("""        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS. */
            fs_device = ntfsdev_get_devoptab();
            break;
#endif
""",
"""#ifdef USBNTFS_BUILD
        case UsbHsFsDriveLogicalUnitFileSystemType_NTFS:    /* NTFS, read-only. */
            fs_device = usbntfsdev_get_devoptab();
            break;
#endif
"""),
])

# block_count is used once NTFS goes through usbntfs.
path = root / "source/usbhsfs_mount.c"
text = path.read_text()
old = "#if !defined(USBHSFS_NTFS) && !defined(USBHSFS_EXT4)\n    NX_IGNORE_ARG(block_count);"
if text.count(old) != 1:
    sys.exit("source/usbhsfs_mount.c: NX_IGNORE_ARG(block_count) anchor not found once")
text = text.replace(old, "#if !defined(USBHSFS_NTFS) && !defined(USBHSFS_EXT4) && !defined(USBNTFS_BUILD)\n"
                         "    NX_IGNORE_ARG(block_count);")

# Mount and unmount, as usbntfs' own patch has them.
anchor = "static bool usbHsFsMountRegisterDevoptabDevice(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx)\n{"
if text.count(anchor) != 1:
    sys.exit("source/usbhsfs_mount.c: usbHsFsMountRegisterDevoptabDevice anchor not found once")
text = text.replace(anchor, """#ifdef USBNTFS_BUILD

/* usbntfs reads the volume's sectors through this: LBAs relative to the volume. */
static bool usbHsFsMountUsbNtfsReadSectors(void *user, uint64_t lba, uint32_t count, uint8_t *buf)
{
    usbntfs_vd *vd = (usbntfs_vd*)user;
    return usbHsFsScsiReadLogicalUnitBlocks((UsbHsFsDriveLogicalUnitContext*)vd->lun_ctx, buf, vd->block_addr + lba, count);
}

static bool usbHsFsMountRegisterUsbNtfsVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx, u64 block_addr, u64 block_count)
{
    UsbHsFsDriveLogicalUnitContext *lun_ctx = (UsbHsFsDriveLogicalUnitContext*)fs_ctx->lun_ctx;
    bool ret = false;

    fs_ctx->usbntfs = calloc(1, sizeof(usbntfs_vd));
    if (!fs_ctx->usbntfs)
    {
        USBHSFS_LOG_MSG("Failed to allocate memory for the NTFS volume! (interface %d, LUN %u, FS %u).", lun_ctx->usb_if_id, lun_ctx->lun, fs_ctx->fs_idx);
        goto end;
    }

    fs_ctx->usbntfs->lun_ctx = lun_ctx;
    fs_ctx->usbntfs->block_addr = block_addr;

    /* Mount the volume read-only. Any write through the devoptab fails with EROFS. */
    fs_ctx->usbntfs->volume = usbntfs_mount(usbHsFsMountUsbNtfsReadSectors, fs_ctx->usbntfs, lun_ctx->block_length, block_count * (u64)lun_ctx->block_length);
    if (!fs_ctx->usbntfs->volume)
    {
        USBHSFS_LOG_MSG("Failed to mount NTFS volume! (interface %d, LUN %u, FS %u).", lun_ctx->usb_if_id, lun_ctx->lun, fs_ctx->fs_idx);
        goto end;
    }

    fs_ctx->flags |= UsbHsFsMountFlags_ReadOnly;

    /* Register devoptab device. */
    if (!usbHsFsMountRegisterDevoptabDevice(fs_ctx)) goto end;

    ret = true;

end:
    if (!ret && fs_ctx->usbntfs)
    {
        if (fs_ctx->usbntfs->volume) usbntfs_unmount(fs_ctx->usbntfs->volume);
        free(fs_ctx->usbntfs);
        fs_ctx->usbntfs = NULL;
    }

    return ret;
}

static void usbHsFsMountUnregisterUsbNtfsVolume(UsbHsFsDriveLogicalUnitFileSystemContext *fs_ctx)
{
    if (!fs_ctx->usbntfs) return;
    usbntfs_unmount(fs_ctx->usbntfs->volume);
    free(fs_ctx->usbntfs);
    fs_ctx->usbntfs = NULL;
}

#endif  /* USBNTFS_BUILD */

""" + anchor)
path.write_text(text)
print("libusbhsfs: usbntfs added")
