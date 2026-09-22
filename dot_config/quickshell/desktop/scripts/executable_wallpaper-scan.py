#!/usr/bin/env python3
import os
import sys
import json
import ctypes
import ctypes.util

DIRS = [
    os.path.expanduser("~/Wallpapers"),
    os.path.expanduser("~/.local/share/aether/wallpapers")
]
EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".avif"}

# Setup statx for fast birthtime/creation time resolution
libc = None
try:
    libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
except Exception:
    pass

class struct_statx_timestamp(ctypes.Structure):
    _fields_ = [
        ("tv_sec", ctypes.c_int64),
        ("tv_nsec", ctypes.c_uint32),
        ("__reserved", ctypes.c_int32),
    ]

class struct_statx(ctypes.Structure):
    _fields_ = [
        ("stx_mask", ctypes.c_uint32),
        ("stx_blksize", ctypes.c_uint32),
        ("stx_attributes", ctypes.c_uint64),
        ("stx_nlink", ctypes.c_uint32),
        ("stx_uid", ctypes.c_uint32),
        ("stx_gid", ctypes.c_uint32),
        ("stx_mode", ctypes.c_uint16),
        ("__spare0", ctypes.c_uint16 * 1),
        ("stx_ino", ctypes.c_uint64),
        ("stx_size", ctypes.c_uint64),
        ("stx_blocks", ctypes.c_uint64),
        ("stx_attributes_mask", ctypes.c_uint64),
        ("stx_atime", struct_statx_timestamp),
        ("stx_btime", struct_statx_timestamp),
        ("stx_ctime", struct_statx_timestamp),
        ("stx_mtime", struct_statx_timestamp),
    ]

AT_FDCWD = -100
STATX_BASIC_STATS = 0x000007ff
STATX_BTIME = 0x00000800
FLAGS = STATX_BASIC_STATS | STATX_BTIME

def scan():
    files = []
    seen = set()
    sx = struct_statx()
    has_statx = hasattr(libc, "statx") if libc else False

    for d in DIRS:
        if not os.path.isdir(d):
            continue
        for root, _, fnames in os.walk(d):
            for fname in fnames:
                ext = os.path.splitext(fname)[1].lower()
                if ext in EXTENSIONS:
                    full = os.path.join(root, fname)
                    real = os.path.realpath(full)
                    if real in seen:
                        continue
                    seen.add(real)

                    if has_statx:
                        try:
                            bpath = real.encode("utf-8")
                            if libc.statx(AT_FDCWD, bpath, 0, FLAGS, ctypes.byref(sx)) == 0:
                                btime = sx.stx_btime.tv_sec if sx.stx_btime.tv_sec > 0 else sx.stx_ctime.tv_sec
                                files.append({
                                    "name": fname,
                                    "path": real,
                                    "mtime": int(sx.stx_mtime.tv_sec),
                                    "btime": int(btime),
                                    "size": int(sx.stx_size)
                                })
                                continue
                        except Exception:
                            pass

                    # Fallback to standard os.stat
                    try:
                        st = os.stat(real)
                        btime = int(getattr(st, "st_birthtime", st.st_ctime))
                        files.append({
                            "name": fname,
                            "path": real,
                            "mtime": int(st.st_mtime),
                            "btime": btime,
                            "size": int(st.st_size)
                        })
                    except OSError:
                        pass
    return files

if __name__ == "__main__":
    print(json.dumps(scan()))
