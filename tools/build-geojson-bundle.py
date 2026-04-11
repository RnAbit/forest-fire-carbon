import argparse
import json
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(
        description="Bundle local GeoJSON files into a single geojson.bundle.js for offline drill-down."
    )
    p.add_argument(
        "--input-dir",
        default=str(Path(__file__).resolve().parent.parent / "geojson" / "areas_v3" / "bound"),
        help="Directory containing *_full.json files (default: ./geojson/areas_v3/bound)",
    )
    p.add_argument(
        "--output-prefix",
        default=str(Path(__file__).resolve().parent.parent / "geojson.bundle"),
        help="Output bundle prefix (default: ./geojson.bundle)",
    )
    p.add_argument(
        "--max-part-mb",
        type=float,
        default=24.0,
        help="Max size per part file in MB (default: 24.0)",
    )
    return p.parse_args()


def main():
    args = parse_args()
    in_dir = Path(args.input_dir).resolve()
    out_prefix = Path(args.output_prefix).resolve()

    if not in_dir.exists():
        raise SystemExit(f"Input directory not found: {in_dir}")

    full_files = sorted(in_dir.glob("*_full.json"))
    optional_files = []
    tw_plain = in_dir / "710000.json"
    if tw_plain.exists():
        optional_files.append(tw_plain)

    files = full_files + optional_files
    if not files:
        raise SystemExit(f"No *_full.json files found in: {in_dir}")

    bundle = {}
    for fp in files:
        name = fp.name
        if name.endswith("_full.json"):
            adcode = name.replace("_full.json", "")
        elif name.endswith(".json"):
            adcode = name.replace(".json", "")
        else:
            continue
        try:
            # adcode should be digits; keep as string regardless
            with fp.open("r", encoding="utf-8") as f:
                obj = json.load(f)
        except Exception as e:
            raise SystemExit(f"Failed reading {fp}: {e}")
        bundle[str(adcode)] = obj

    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    max_bytes = int(args.max_part_mb * 1024 * 1024)
    if max_bytes <= 0:
        raise SystemExit("max-part-mb must be > 0")

    # Convert to compact per-entry payload first, then split by target size.
    entries = []
    for k, v in bundle.items():
        entries.append((k, json.dumps(v, ensure_ascii=False, separators=(",", ":"))))

    parts = []
    current = []
    current_bytes = 0
    overhead = 512  # wrapper buffer
    for k, v_json in entries:
        # '{"k":<json>}' plus comma when needed
        piece = len(k.encode("utf-8")) + len(v_json.encode("utf-8")) + 6
        if current and (current_bytes + piece + overhead > max_bytes):
            parts.append(current)
            current = []
            current_bytes = 0
        current.append((k, v_json))
        current_bytes += piece
    if current:
        parts.append(current)

    # Write part files:
    # geojson.bundle.part1.js, geojson.bundle.part2.js, ...
    written = []
    for i, part in enumerate(parts, start=1):
        obj_text = "{" + ",".join([f"\"{k}\":{v}" for k, v in part]) + "}"
        js = (
            "/* Auto-generated part. Do not edit manually. */\n"
            "(function(){\n"
            "  if (typeof window === 'undefined') return;\n"
            "  window.__GEOJSON_BUNDLE__ = Object.assign(window.__GEOJSON_BUNDLE__ || {}, "
            + obj_text
            + ");\n"
            "})();\n"
        )
        out_path = out_prefix.with_name(out_prefix.name + f".part{i}.js")
        with out_path.open("w", encoding="utf-8", newline="\n") as f:
            f.write(js)
        written.append(out_path)

    # Also write a small manifest for humans/tools.
    manifest_path = out_prefix.with_name(out_prefix.name + ".manifest.json")
    manifest = {
        "parts": [p.name for p in written],
        "count": len(written),
        "max_part_mb": args.max_part_mb,
    }
    with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"Bundled {len(files)} files into {len(written)} parts:")
    for p in written:
        size_mb = p.stat().st_size / (1024 * 1024)
        print(f"  - {p} ({size_mb:.2f} MB)")
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()

