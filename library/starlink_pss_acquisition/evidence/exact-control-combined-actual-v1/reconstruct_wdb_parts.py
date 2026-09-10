"""Losslessly reconstruct the saved WDB in a new directory; never overwrite."""

import argparse
import gzip
import hashlib
import json
import re
import shutil
from pathlib import Path

MAX_PART_BYTES = 40 * 1024 * 1024


def identity(path):
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            size += len(block)
            digest.update(block)
    return {"bytes": size, "sha256": digest.hexdigest()}


def validate(manifest):
    if manifest.get("format") != "starlink-portable-gzip-parts-v1":
        raise ValueError("unknown portable format")
    for name in ("gzip", "uncompressed"):
        item = manifest[name]
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", item["name"]) or item["name"] in {
            ".",
            "..",
        }:
            raise ValueError("unsafe output filename")
        if type(item["bytes"]) is not int or item["bytes"] <= 0:
            raise ValueError("invalid output size")
        if not re.fullmatch(r"[0-9a-f]{64}", item["sha256"]):
            raise ValueError("invalid output digest")
    if manifest["gzip"]["name"] != manifest["uncompressed"]["name"] + ".gz":
        raise ValueError("gzip/uncompressed filenames differ")
    if manifest.get("max_part_bytes") != MAX_PART_BYTES:
        raise ValueError("unexpected portable part limit")
    parts = manifest["parts"]
    if not isinstance(parts, list) or not parts:
        raise ValueError("missing part inventory")
    total = 0
    for index, part in enumerate(parts):
        if type(part["index"]) is not int or part["index"] != index:
            raise ValueError("missing or reordered part index")
        if part["name"] != f"{manifest['gzip']['name']}.part{index:03d}":
            raise ValueError("missing or reordered part filename")
        if type(part["bytes"]) is not int or not 0 < part["bytes"] <= MAX_PART_BYTES:
            raise ValueError("invalid part size")
        if not re.fullmatch(r"[0-9a-f]{64}", part["sha256"]):
            raise ValueError("invalid part digest")
        total += part["bytes"]
    if total != manifest["gzip"]["bytes"]:
        raise ValueError("part size total differs")


def reconstruct(manifest_path, output_dir):
    # mkdir and exclusive file creation also protect against a concurrent
    # creator. Failures retain any newly created output for inspection.
    if output_dir.exists():
        raise FileExistsError("refusing to overwrite reconstruction evidence")
    manifest = json.loads(manifest_path.read_text())
    validate(manifest)
    for part in manifest["parts"]:
        if identity(manifest_path.parent / part["name"]) != {
            "bytes": part["bytes"],
            "sha256": part["sha256"],
        }:
            raise ValueError(f"part hash/size mismatch: {part['name']}")
    output_dir.mkdir()
    assembled = output_dir / manifest["gzip"]["name"]
    with assembled.open("xb") as target:
        for part in manifest["parts"]:
            with (manifest_path.parent / part["name"]).open("rb") as source:
                shutil.copyfileobj(source, target, 1024 * 1024)
    compressed = identity(assembled)
    if compressed != {key: manifest["gzip"][key] for key in ("bytes", "sha256")}:
        raise ValueError("assembled gzip hash/size mismatch")
    raw = output_dir / manifest["uncompressed"]["name"]
    with gzip.open(assembled, "rb") as source, raw.open("xb") as target:
        shutil.copyfileobj(source, target, 1024 * 1024)
    uncompressed = identity(raw)
    if uncompressed != {
        key: manifest["uncompressed"][key] for key in ("bytes", "sha256")
    }:
        raise ValueError("uncompressed WDB hash/size mismatch")
    return {
        "parts": len(manifest["parts"]),
        "gzip": compressed,
        "uncompressed": uncompressed,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(reconstruct(args.manifest, args.output_dir), sort_keys=True))


if __name__ == "__main__":
    main()
