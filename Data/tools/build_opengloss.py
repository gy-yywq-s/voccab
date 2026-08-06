#!/usr/bin/env python3
"""Builds the downloadable OpenGloss resource database.

Reads the eight parquet shards of mjbommar/opengloss-dictionary (Hugging
Face, CC-BY 4.0) and writes opengloss.sqlite with only the fields the app
renders — the 11 KB-per-word markdown blob and the 9.1M-edge graph are
dropped, which is what turns 1.28 GB of parquet into a few hundred MB.

Usage:
    pip install pyarrow
    python3 build_opengloss.py --shards-dir ./shards --out opengloss.sqlite

Download the shards first:
    for i in $(seq -w 0 7); do
      curl -L -O "https://huggingface.co/datasets/mjbommar/opengloss-dictionary/resolve/main/data/train-000${i}-of-00008.parquet"
    done

The app expects the result at:
    Application Support/Resources/dict.opengloss/opengloss.sqlite
(one download powers the OpenGloss, OpenGloss Usage and OpenGloss Story
dictionaries).
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

MAX_SYNONYMS = 8      # per sense
MAX_ANTONYMS = 4      # per sense
MAX_EXAMPLES = 2      # per sense
MAX_COLLOCATIONS = 24
MAX_FORMS = 12


def compact_senses(senses):
    out = []
    for sense in senses or []:
        definition = (sense.get("definition") or "").strip()
        if not definition:
            continue
        out.append({
            "pos": sense.get("part_of_speech") or "",
            "definition": definition,
            "synonyms": (sense.get("synonyms") or [])[:MAX_SYNONYMS],
            "antonyms": (sense.get("antonyms") or [])[:MAX_ANTONYMS],
            "examples": (sense.get("examples") or [])[:MAX_EXAMPLES],
        })
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shards-dir", required=True,
                        help="Directory containing train-*.parquet")
    parser.add_argument("--out", default="opengloss.sqlite")
    args = parser.parse_args()

    try:
        import pyarrow.parquet as pq
    except ImportError:
        sys.exit("pip install pyarrow first")

    shards = sorted(Path(args.shards_dir).glob("train-*.parquet"))
    if not shards:
        sys.exit(f"No train-*.parquet shards in {args.shards_dir}")

    out = Path(args.out)
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.execute("""
        CREATE TABLE entries (
            word TEXT PRIMARY KEY COLLATE NOCASE,
            senses TEXT NOT NULL,          -- JSON [{pos, definition, synonyms, antonyms, examples}]
            collocations TEXT NOT NULL,    -- tab-separated
            inflections TEXT NOT NULL,     -- tab-separated
            derivations TEXT NOT NULL,     -- tab-separated
            etymology TEXT NOT NULL,
            encyclopedia TEXT NOT NULL
        )
    """)

    total = kept = 0
    for shard in shards:
        for batch in pq.ParquetFile(shard).iter_batches(batch_size=2000):
            for row in batch.to_pylist():
                total += 1
                senses = compact_senses(row.get("senses"))
                etymology = (row.get("etymology_summary") or "").strip()
                encyclopedia = (row.get("encyclopedia_entry") or "").strip()
                if not senses and not etymology and not encyclopedia:
                    continue
                db.execute(
                    "INSERT OR IGNORE INTO entries VALUES (?,?,?,?,?,?,?)",
                    (
                        row["word"],
                        json.dumps(senses, ensure_ascii=False, separators=(",", ":")),
                        "\t".join((row.get("all_collocations") or [])[:MAX_COLLOCATIONS]),
                        "\t".join((row.get("all_inflections") or [])[:MAX_FORMS]),
                        "\t".join((row.get("all_derivations") or [])[:MAX_FORMS]),
                        etymology,
                        encyclopedia,
                    ))
                kept += 1
        db.commit()
        print(f"{shard.name}: {kept}/{total} entries so far")

    db.execute("VACUUM")
    db.commit()
    db.close()
    print(f"Done: {kept} entries -> {out} ({out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
