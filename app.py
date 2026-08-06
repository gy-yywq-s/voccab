"""Voccab resource server.

Serves the app's downloadable resources from the droplet so devices never
need to reach Hugging Face directly:

    GET /                                   status JSON (build progress, sizes)
    GET /resources/opengloss.sqlite         the converted OpenGloss database
    GET /resources/en_US-libritts_r-medium.onnx        Piper voice model
    GET /resources/en_US-libritts_r-medium.onnx.json   Piper model config

On first boot a background worker (one per data dir, elected by lockfile)
mirrors the Piper files and builds the OpenGloss database: it streams the
eight parquet shards one at a time into the persistent data dir, converts
each into SQLite with modest memory (batch iteration), and deletes the
shard before fetching the next — peak transient disk is one shard
(~170 MB) plus the growing database, not the full 1.3 GB dataset.
Files are served with Range support so URLSession downloads can resume.
"""

import json
import os
import sqlite3
import threading
import urllib.request

from flask import Flask, jsonify, send_from_directory

DATA_DIR = os.environ.get("HOSTD_DATA_DIR", os.path.abspath("data"))
RESOURCES = os.path.join(DATA_DIR, "resources")
WORK = os.path.join(DATA_DIR, "work")

HF = "https://huggingface.co"
PIPER_FILES = [
    ("en_US-libritts_r-medium.onnx",
     f"{HF}/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx"),
    ("en_US-libritts_r-medium.onnx.json",
     f"{HF}/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx.json"),
]
OPENGLOSS_SHARDS = [
    f"{HF}/datasets/mjbommar/opengloss-dictionary/resolve/main/data/train-{i:05d}-of-00008.parquet"
    for i in range(8)
]
OPENGLOSS_DB = "opengloss.sqlite"

MAX_SYNONYMS, MAX_ANTONYMS, MAX_EXAMPLES = 8, 4, 2
MAX_COLLOCATIONS, MAX_FORMS = 24, 12

state = {"piper": "pending", "opengloss": "pending", "detail": ""}
app = Flask(__name__)


def fetch(url, dest):
    tmp = dest + ".part"
    with urllib.request.urlopen(url, timeout=120) as response, open(tmp, "wb") as out:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
    os.replace(tmp, dest)


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


def build_opengloss():
    import pyarrow.parquet as pq

    final = os.path.join(RESOURCES, OPENGLOSS_DB)
    if os.path.exists(final):
        state["opengloss"] = "ready"
        return
    building = os.path.join(WORK, OPENGLOSS_DB)
    if os.path.exists(building):
        os.remove(building)
    db = sqlite3.connect(building)
    db.execute("""
        CREATE TABLE entries (
            word TEXT PRIMARY KEY COLLATE NOCASE,
            senses TEXT NOT NULL,
            collocations TEXT NOT NULL,
            inflections TEXT NOT NULL,
            derivations TEXT NOT NULL,
            etymology TEXT NOT NULL,
            encyclopedia TEXT NOT NULL
        )
    """)
    for index, url in enumerate(OPENGLOSS_SHARDS):
        state["opengloss"] = f"building shard {index + 1}/8"
        shard = os.path.join(WORK, f"shard-{index}.parquet")
        if not os.path.exists(shard):
            fetch(url, shard)
        for batch in pq.ParquetFile(shard).iter_batches(batch_size=1000):
            for row in batch.to_pylist():
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
        db.commit()
        os.remove(shard)
    db.execute("VACUUM")
    db.commit()
    db.close()
    os.replace(building, final)
    state["opengloss"] = "ready"


def build_worker():
    try:
        state["piper"] = "mirroring"
        for name, url in PIPER_FILES:
            dest = os.path.join(RESOURCES, name)
            if not os.path.exists(dest):
                fetch(url, dest)
        state["piper"] = "ready"
        build_opengloss()
    except Exception as error:  # surfaced in the status JSON, not lost to logs
        state["detail"] = f"{type(error).__name__}: {error}"
        for key in ("piper", "opengloss"):
            if state[key] != "ready":
                state[key] = "failed"


def start_worker_once():
    os.makedirs(RESOURCES, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    # One builder per boot even with several gunicorn workers: /tmp is
    # private to the service and emptied on every restart, so a crashed
    # build simply tries again next boot.
    lock = os.path.join(os.environ.get("TMPDIR", "/tmp"), "builder.lock")
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        return
    threading.Thread(target=build_worker, daemon=True).start()


@app.route("/")
def status():
    sizes = {}
    if os.path.isdir(RESOURCES):
        for name in sorted(os.listdir(RESOURCES)):
            sizes[name] = os.path.getsize(os.path.join(RESOURCES, name))
    return jsonify({"state": state, "files": sizes})


@app.route("/resources/<path:name>")
def resource(name):
    return send_from_directory(RESOURCES, name, conditional=True)


start_worker_once()
