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
ORT_REPACK = "onnxruntime-slim.xcframework.zip"

MAX_SYNONYMS, MAX_ANTONYMS, MAX_EXAMPLES = 8, 4, 2
MAX_COLLOCATIONS, MAX_FORMS = 24, 12

state = {"frameworks": "pending", "piper": "pending", "opengloss": "pending",
         "opengloss_gz": "pending", "detail": ""}
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
    import plistlib
    import stat
    import zipfile

    final = os.path.join(RESOURCES, ORT_REPACK)
    if os.path.exists(final):
        state["frameworks"] = "ready"
        return

    state["frameworks"] = "fetching"
    source = os.path.join(WORK, "onnxruntime-original.zip")
    if not os.path.exists(source):
        fetch(ORT_SOURCE, source)

    # Zip to zip, never touching the filesystem in between: entry order
    # follows the source and every timestamp is fixed, so rebuilding this
    # file byte-for-byte reproduces the checksum the app pins.
    state["frameworks"] = "repacking"
    fixed_time = (1980, 1, 1, 0, 0, 0)
    with zipfile.ZipFile(source) as src, \
            zipfile.ZipFile(final + ".part", "w", zipfile.ZIP_DEFLATED) as out:
        for info in src.infolist():
            if info.is_dir():
                continue
            mode = (info.external_attr >> 16) & 0o170000
            if mode == stat.S_IFLNK:
                continue          # symlinked alias of the real static library
            # Keep paths rooted at the .xcframework, whatever wraps it.
            parts = info.filename.split("/")
            root = next((i for i, p in enumerate(parts) if p.endswith(".xcframework")), None)
            if root is None:
                continue
            name = "/".join(parts[root:])
            if "/Headers/" in name:
                continue          # the colliding module.modulemap lives here
            payload = src.read(info)
            if name.endswith(".xcframework/Info.plist"):
                plist = plistlib.loads(payload)
                for library in plist.get("AvailableLibraries", []):
                    library.pop("HeadersPath", None)
                payload = plistlib.dumps(plist)
            entry = zipfile.ZipInfo(name, date_time=fixed_time)
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            out.writestr(entry, payload)
    os.replace(final + ".part", final)
    os.remove(source)
    state["frameworks"] = "ready"


STALE_FILES = ["onnxruntime-noheaders.xcframework.zip", "en_US-libritts_r-medium.onnx.json"]


def build_gzip():
    """Transfer-sized copy of the OpenGloss database: the text columns
    compress to roughly a quarter, so devices pull ~230 MB instead of
    ~815 MB and inflate locally."""
    import gzip

    src = os.path.join(RESOURCES, OPENGLOSS_DB)
    final = src + ".gz"
    if os.path.exists(final):
        state["opengloss_gz"] = "ready"
        return
    if not os.path.exists(src):
        return
    state["opengloss_gz"] = "compressing"
    with open(src, "rb") as inp, gzip.open(final + ".part", "wb", compresslevel=6) as out:
        while chunk := inp.read(1 << 20):
            out.write(chunk)
    os.replace(final + ".part", final)
    state["opengloss_gz"] = "ready"


def build_worker():
    try:
        for name in STALE_FILES:
            path = os.path.join(RESOURCES, name)
            if os.path.exists(path):
                os.remove(path)
        build_frameworks()
        build_piper()
        build_opengloss()
        build_gzip()
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
