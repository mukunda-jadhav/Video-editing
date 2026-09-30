"""Inspect release APK native ELF alignment, size and digest without extra packages.

Usage: python scripts/verify_apk.py build/app/outputs/flutter-apk/*-release.apk
APK ZIP alignment and device execution are separate checks documented in TESTING.md.
"""
import glob
import hashlib
import json
from pathlib import Path
import struct
import sys
from zipfile import ZipFile


def inspect_apk(path):
    libraries = []
    with ZipFile(path) as archive:
        for name in sorted(archive.namelist()):
            if not name.startswith("lib/") or not name.endswith(".so"):
                continue
            data = archive.read(name)
            if data[:4] != b"\x7fELF" or data[4] not in (1, 2):
                raise ValueError(f"Invalid native ELF: {name}")
            endian = "<" if data[5] == 1 else ">"
            is_64 = data[4] == 2
            offset = struct.unpack_from(endian + ("Q" if is_64 else "I"), data, 32 if is_64 else 28)[0]
            size, count = struct.unpack_from(endian + "HH", data, 54 if is_64 else 42)
            aligns = []
            for index in range(count):
                header = offset + index * size
                if struct.unpack_from(endian + "I", data, header)[0] == 1:
                    aligns.append(struct.unpack_from(endian + ("Q" if is_64 else "I"), data, header + (48 if is_64 else 28))[0])
            if not aligns:
                raise ValueError(f"No load segments: {name}")
            # Android's 16 KB page-size requirement concerns its 64-bit ABIs.
            required = name.split("/")[1] in {"arm64-v8a", "x86_64"}
            libraries.append({
                "path": name,
                "minimum_load_alignment": min(aligns),
                "requires_16kb": required,
                "passes": not required or min(aligns) >= 16384,
            })
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "apk": path.as_posix(),
        "bytes": path.stat().st_size,
        "sha256": digest.hexdigest(),
        "elf_alignment_passed": bool(libraries) and all(item["passes"] for item in libraries),
        "native_libraries": libraries,
    }


def main():
    paths = sorted({Path(path) for pattern in sys.argv[1:] for path in glob.glob(pattern)})
    if not paths:
        raise SystemExit("Provide at least one existing APK path or glob.")
    reports = [inspect_apk(path) for path in paths]
    print(json.dumps(reports, indent=2))
    return 0 if all(report["elf_alignment_passed"] for report in reports) else 1


if __name__ == "__main__":
    sys.exit(main())
