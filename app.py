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
PIPER_MODEL = "en_US-libritts_r-medium.onnx"
PIPER_PACKAGE = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/"
    "vits-piper-en_US-libritts_r-medium.tar.bz2"
)
OPENGLOSS_SHARDS = [
    f"{HF}/datasets/mjbommar/opengloss-dictionary/resolve/main/data/train-{i:05d}-of-00008.parquet"
    for i in range(8)
]
OPENGLOSS_DB = "opengloss.sqlite"

# Prebuilt sherpa-onnx runtime, repackaged here without headers (see
# build_frameworks) so Xcode can link it alongside sherpa-onnx itself.
ORT_SOURCE = ("https://github.com/willwade/sherpa-onnx-spm/releases/download/"
              "1.13.3/onnxruntime.xcframework.zip")
ORT_REPACK = "onnxruntime-noheaders.xcframework.zip"

MAX_SYNONYMS, MAX_ANTONYMS, MAX_EXAMPLES = 8, 4, 2
MAX_COLLOCATIONS, MAX_FORMS = 24, 12

state = {"frameworks": "pending", "piper": "pending", "opengloss": "pending", "detail": ""}
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
    # A redeploy restarts the worker, so record how far the build got and
    # resume there instead of throwing away an hour of shards.
    building = os.path.join(WORK, OPENGLOSS_DB)
    progress_file = os.path.join(WORK, "opengloss.progress")
    done = 0
    if os.path.exists(building) and os.path.exists(progress_file):
        with open(progress_file) as f:
            done = int((f.read().strip() or "0"))
    elif os.path.exists(building):
        os.remove(building)
    db = sqlite3.connect(building)
    db.execute("""
        CREATE TABLE IF NOT EXISTS entries (
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
        if index < done:
            continue
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
        with open(progress_file, "w") as f:
            f.write(str(index + 1))
    db.execute("VACUUM")
    db.commit()
    db.close()
    os.replace(building, final)
    os.remove(progress_file)
    state["opengloss"] = "ready"


def stored_zip(entries):
    """Minimal store-only (method 0) ZIP, matching the app's own reader."""
    import struct
    import zlib

    out, central, offset = bytearray(), bytearray(), 0
    for name, payload in entries:
        raw = name.encode()
        crc = zlib.crc32(payload) & 0xFFFFFFFF
        header = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0, 0,
                             crc, len(payload), len(payload), len(raw), 0)
        central += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, 0, 0, 0,
                               crc, len(payload), len(payload), len(raw),
                               0, 0, 0, 0, 0, offset) + raw
        offset += len(header) + len(raw) + len(payload)
        out += header + raw + payload
    start = len(out)
    out += central
    out += struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries),
                       len(central), start, 0)
    return bytes(out)


def build_piper():
    """The Piper voice as sherpa-onnx needs it: the ONNX model, the token
    table, and espeak-ng-data (zipped, since it is a directory of ~200
    files). Taken from the sherpa-onnx model package so the tokens and the
    model are guaranteed to match."""
    import tarfile

    model = os.path.join(RESOURCES, PIPER_MODEL)
    tokens = os.path.join(RESOURCES, "tokens.txt")
    espeak = os.path.join(RESOURCES, "espeak-ng-data.zip")
    if all(os.path.exists(p) for p in (model, tokens, espeak)):
        state["piper"] = "ready"
        return

    state["piper"] = "fetching model package"
    archive = os.path.join(WORK, "piper.tar.bz2")
    if not os.path.exists(archive):
        fetch(PIPER_PACKAGE, archive)

    state["piper"] = "unpacking"
    espeak_entries = []
    with tarfile.open(archive, "r:bz2") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            # Paths inside the package are <dir>/<name>; keep the tail.
            parts = member.name.split("/", 1)
            rel = parts[1] if len(parts) > 1 else parts[0]
            if rel.endswith(".onnx"):
                with tar.extractfile(member) as src, open(model + ".part", "wb") as out:
                    while chunk := src.read(1 << 20):
                        out.write(chunk)
                os.replace(model + ".part", model)
            elif rel == "tokens.txt":
                with tar.extractfile(member) as src, open(tokens + ".part", "wb") as out:
                    out.write(src.read())
                os.replace(tokens + ".part", tokens)
            elif rel.startswith("espeak-ng-data/"):
                with tar.extractfile(member) as src:
                    espeak_entries.append((rel, src.read()))

    state["piper"] = "packing espeak data"
    with open(espeak + ".part", "wb") as out:
        out.write(stored_zip(espeak_entries))
    os.replace(espeak + ".part", espeak)
    os.remove(archive)
    state["piper"] = "ready"


def build_frameworks():
    """Repackage the onnxruntime xcframework without its headers.

    Both sherpa-onnx and onnxruntime ship a `Headers/module.modulemap`, and
    Xcode copies every binary target's headers into one `include/`
    directory — two files, one destination, build refused. Nothing in the
    app imports onnxruntime directly (only sherpa-onnx's C API), so the
    headers come out and the collision disappears. Symlinks are skipped:
    each slice's Info.plist already points at the real `libonnxruntime.a`.
    """
    import shutil
    import zipfile

    final = os.path.join(RESOURCES, ORT_REPACK)
    if os.path.exists(final):
        state["frameworks"] = "ready"
        return

    state["frameworks"] = "fetching"
    source = os.path.join(WORK, "onnxruntime-original.zip")
    if not os.path.exists(source):
        fetch(ORT_SOURCE, source)

    state["frameworks"] = "repacking"
    extracted = os.path.join(WORK, "ort")
    shutil.rmtree(extracted, ignore_errors=True)
    with zipfile.ZipFile(source) as zf:
        zf.extractall(extracted)

    root = None
    for base, dirs, _ in os.walk(extracted):
        for name in dirs:
            if name.endswith(".xcframework"):
                root = os.path.join(base, name)
                break
        if root:
            break
    if root is None:
        raise RuntimeError("no .xcframework inside the onnxruntime archive")

    import plistlib
    plist_path = os.path.join(root, "Info.plist")
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
    for library in plist.get("AvailableLibraries", []):
        library.pop("HeadersPath", None)
    with open(plist_path, "wb") as f:
        plistlib.dump(plist, f)
    for base, dirs, _ in os.walk(root):
        for name in list(dirs):
            if name == "Headers":
                shutil.rmtree(os.path.join(base, name), ignore_errors=True)
                dirs.remove(name)

    with zipfile.ZipFile(final + ".part", "w", zipfile.ZIP_DEFLATED) as out:
        for base, _, files in os.walk(root):
            for name in files:
                path = os.path.join(base, name)
                if os.path.islink(path):
                    continue
                out.write(path, os.path.relpath(path, os.path.dirname(root)))
    os.replace(final + ".part", final)
    shutil.rmtree(extracted, ignore_errors=True)
    os.remove(source)
    state["frameworks"] = "ready"


def build_worker():
    try:
        build_frameworks()
        build_piper()
        build_opengloss()
    except Exception as error:  # surfaced in the status JSON, not lost to logs
        state["detail"] = f"{type(error).__name__}: {error}"
        for key in ("frameworks", "piper", "opengloss"):
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
