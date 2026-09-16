#!/usr/bin/env python3
"""Enable ChatGPT's existing translucent chrome on Linux."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile


MARKER = "/* chatgpt-translucent-bars */"


def replace_once(source, pattern, replacement):
    result, count = re.subn(pattern, replacement, source)
    if count != 1:
        raise ValueError(f"Expected one patch location, found {count}: {pattern}")
    return result


def patch_main(source):
    # Only the main window uses the sidebar/titlebar layout. Keep the app's
    # existing opaque-surface notifications and CSS in charge of rendering it.
    source = replace_once(
        source,
        r"shouldAlwaysUseOpaqueWindowSurface\((\w+)\)\{return",
        lambda match: (
            f"shouldAlwaysUseOpaqueWindowSurface({match[1]}){{\n"
            f"{MARKER}\n"
            f'if (process.platform === "linux" && {match[1]} === "primary") return false;\n'
            "return"
        ),
    )
    backdrop = re.findall(
        r"webPreferences:\w+\}\);this\.applyWindowBackdrop\(\w+,(\w+),!0\)", source
    )
    if len(backdrop) != 1:
        raise ValueError("Could not identify the main window's appearance argument")
    return replace_once(
        source,
        r"(supportsWindowTiling:\w+,\.\.\.\w+,)(minWidth:)",
        lambda match: (
            f"{match[1]}\n"
            f'...(process.platform === "linux" && {backdrop[0]} === "primary"\n'
            "    ? {transparent: true} : {}),\n"
            f"{match[2]}"
        ),
    ).encode()


def patch_archive(path):
    with path.open("rb") as archive:
        size, header_size, payload_size, json_size = struct.unpack("<4I", archive.read(16))
        if size != 4 or payload_size != header_size - 4:
            raise ValueError("Unexpected ASAR header")
        header = json.loads(archive.read(json_size))
        files = header["files"][".vite"]["files"]["build"]["files"]
        mains = [entry for name, entry in files.items() if re.fullmatch(r"main-[\w-]+\.js", name)]
        if len(mains) != 1:
            raise ValueError("Expected one main JavaScript bundle")
        entry = mains[0]
        data_start = 8 + header_size
        archive.seek(data_start + int(entry["offset"]))
        source = archive.read(entry["size"]).decode()
        if MARKER in source:
            print(f"Already patched: {path}")
            return
        patched = patch_main(source)

        # Append the bundle and retain every other offset. Keeping the header's
        # reserved size also leaves the running app's cached ASAR index valid.
        archive.seek(0, 2)
        entry["offset"] = str(archive.tell() - data_start)
        entry["size"] = len(patched)
        integrity = entry["integrity"]
        if integrity["algorithm"] != "SHA256":
            raise ValueError("Unexpected ASAR integrity algorithm")
        block_size = integrity["blockSize"]
        integrity["hash"] = hashlib.sha256(patched).hexdigest()
        integrity["blocks"] = [
            hashlib.sha256(patched[start:start + block_size]).hexdigest()
            for start in range(0, len(patched), block_size)
        ]
        encoded = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
        padding = header_size - 8 - len(encoded)
        if padding < 0:
            raise ValueError("ASAR header has no room for this patch; archive left unchanged")

        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                output.write(struct.pack("<4I", 4, header_size, payload_size, len(encoded)))
                output.write(encoded + b"\0" * padding)
                archive.seek(data_start)
                shutil.copyfileobj(archive, output)
                output.write(patched)
                output.flush()
                shutil.copystat(path, temporary)
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    print(f"Patched: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="ASAR archive inside the package staging directory")
    args = parser.parse_args()
    patch_archive(args.archive)
