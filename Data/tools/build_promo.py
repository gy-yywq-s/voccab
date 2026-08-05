#!/usr/bin/env python3
"""Builds the home-page promo carousel from public-domain poster art.

The promo demonstrates photo word-lookup, so every slide must actually
contain legible English text. Pipeline:

1. Harvest candidate files from Wikimedia Commons poster categories
   (WPA serigraphs, vintage US travel/war posters — all public domain).
2. OCR each image with tesseract and keep only images where a real
   dictionary word (verified against voccab-dict.sqlite) is read with
   high confidence.
3. Crop to the app's 3:4 frame so the word stays visible, resize to
   900x1200 JPEG, and record the word's normalized bounding box for the
   in-app highlight + lookup card.
4. Emit Apps/Shared/PromoAssets.xcassets imagesets and PromoData.swift.

Usage: python3 Data/tools/build_promo.py [--target 100]
"""
import argparse
import concurrent.futures as futures
import io
import json
import re
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
DICT_DB = REPO / "Data" / "dict" / "voccab-dict.sqlite"
ASSET_DIR = REPO / "Apps" / "Shared" / "PromoAssets.xcassets"
SWIFT_OUT = REPO / "Apps" / "Shared" / "PromoData.swift"

API = "https://commons.wikimedia.org/w/api.php"
HEADERS = {"User-Agent": "VoccabPromoBuilder/1.0 (asset pipeline for an educational app)"}

ROOT_CATS = [
    "Category:Work Projects Administration Poster Collection",
    "Category:WPA posters, National Park Service",
    "Category:Works Progress Administration posters by state",
    "Category:Federal Art Project",
    "Category:United States travel posters",
    "Category:Travel posters",
    "Category:American World War I posters",
]
MAX_FILES = 900
THUMB_WIDTH = 1000
OUT_W, OUT_H = 900, 1200
MIN_CONF = 75
MIN_RANK = 1200          # skip ultra-common words: lookup demo should teach
MAX_RANK = 60000
MAX_WORD_REUSE = 1

# Words rejected on curation review: proper nouns (people/places), dated or
# offensive terms, and non-words that slipped through the dictionary check.
CURATED_OUT = {
    "negro", "womens", "salem", "nassau", "wheaton", "rockefeller",
    "holbrook", "harwood", "sioux", "euclid", "bessemer", "phillips",
    "newbury", "howard", "mason", "lyndon", "macbeth", "michigan",
    "brooklyn", "cairo", "lexington", "jefferson", "capitol", "yankee",
    "greek", "southside", "fontana", "niagara", "berlin",
}

# Additional text-rich public-domain pools for top-up passes.
TOPUP_CATS = [
    "Category:American Red Cross posters",
    "Category:United States Army recruiting posters",
    "Category:United States Navy recruiting posters",
    "Category:United States Marine Corps recruiting posters",
    "Category:Liberty bond posters",
]

BLACKLIST = {
    # proper nouns / poster boilerplate that read as words
    "america", "american", "americans", "york", "yorker", "carolina",
    "dakota", "virginia", "georgia", "washington", "oregon", "montana",
    "arizona", "illinois", "chicago", "boston", "florida", "texas",
    "january", "february", "march", "april", "june", "july", "august",
    "september", "october", "november", "december", "monday", "tuesday",
    "wednesday", "thursday", "friday", "saturday", "sunday",
    "street", "avenue", "admission", "united", "states",
}


_api_lock = None
_last_api_call = [0.0]


def _throttled_fetch(url, timeout):
    """Serialize + pace API calls and back off hard on 429s."""
    global _api_lock
    import threading
    import time
    if _api_lock is None:
        _api_lock = threading.Lock()
    for attempt in range(6):
        with _api_lock:
            wait = 1.2 - (time.time() - _last_api_call[0])
            if wait > 0:
                time.sleep(wait)
            _last_api_call[0] = time.time()
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt < 5:
                import time as _t
                _t.sleep(20 * (attempt + 1))
                continue
            raise
    raise RuntimeError("unreachable")


def api_get(params):
    params = dict(params, format="json")
    url = API + "?" + urllib.parse.urlencode(params)
    return json.loads(_throttled_fetch(url, 60))


def category_members(cat, cmtype):
    members, cont = [], {}
    while True:
        data = api_get({
            "action": "query", "list": "categorymembers", "cmtitle": cat,
            "cmtype": cmtype, "cmlimit": 500, **cont,
        })
        members += [m["title"] for m in data["query"]["categorymembers"]]
        cont = data.get("continue")
        if not cont:
            return members


def harvest_titles():
    seen_cats, files = set(), []
    queue = [(c, 0) for c in ROOT_CATS]
    while queue and len(files) < MAX_FILES:
        cat, depth = queue.pop(0)
        if cat in seen_cats:
            continue
        seen_cats.add(cat)
        try:
            files += [t for t in category_members(cat, "file")
                      if t.lower().endswith((".jpg", ".jpeg", ".png", ".tif", ".tiff"))]
            if depth < 2:
                queue += [(sub, depth + 1) for sub in category_members(cat, "subcat")
                          if "poster" in sub.lower()]
        except Exception as e:
            print(f"  category failed: {cat}: {e}", file=sys.stderr)
    # dedupe preserving order
    seen = set()
    return [t for t in files if not (t in seen or seen.add(t))][:MAX_FILES]


def thumb_urls(titles):
    """title -> thumb url, batched imageinfo queries."""
    out = {}
    for i in range(0, len(titles), 50):
        chunk = titles[i:i + 50]
        try:
            data = api_get({
                "action": "query", "titles": "|".join(chunk),
                "prop": "imageinfo", "iiprop": "url|size",
                "iiurlwidth": THUMB_WIDTH,
            })
        except Exception as e:
            print(f"  imageinfo failed: {e}", file=sys.stderr)
            continue
        for page in data["query"].get("pages", {}).values():
            info = (page.get("imageinfo") or [{}])[0]
            url = info.get("thumburl")
            if url and info.get("width", 0) >= 600:
                out[page["title"]] = url
    return out


def fetch(url):
    return _throttled_fetch(url, 90)


class Dict:
    def __init__(self):
        import threading
        self.conn = sqlite3.connect(DICT_DB, check_same_thread=False)
        self.lock = threading.Lock()

    def lookup(self, word):
        with self.lock:
            row = self.conn.execute(
                "SELECT word, frq, bnc, translation FROM words WHERE word = ? COLLATE NOCASE",
                (word,)).fetchone()
        if not row:
            return None
        rank = row[1] if row[1] else row[2]
        return {"word": row[0], "rank": rank, "translation": row[3]}


def ocr_words(image_path):
    """tesseract TSV -> [(word, conf, (l, t, w, h))]."""
    proc = subprocess.run(
        ["tesseract", str(image_path), "stdout", "--psm", "3", "tsv"],
        capture_output=True, text=True, timeout=120)
    rows = []
    for line in proc.stdout.splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) != 12 or parts[0] != "5":
            continue
        try:
            conf = float(parts[10])
        except ValueError:
            continue
        text = parts[11].strip()
        box = tuple(int(v) for v in parts[6:10])
        rows.append((text, conf, box))
    return rows


def pick_word(rows, dictionary, used_counts):
    """Best OCR word that is a real dictionary word worth looking up."""
    best = None
    for text, conf, box in rows:
        clean = re.sub(r"[^A-Za-z]", "", text)
        if len(clean) < 5 or conf < MIN_CONF or len(clean) != len(text):
            continue
        lower = clean.lower()
        if lower in BLACKLIST or used_counts.get(lower, 0) >= MAX_WORD_REUSE:
            continue
        entry = dictionary.lookup(lower)
        if not entry or not entry["rank"] or not entry["translation"]:
            continue
        if not (MIN_RANK <= entry["rank"] <= MAX_RANK):
            continue
        score = entry["rank"] + conf * 10
        if best is None or score > best[0]:
            best = (score, lower, conf, box)
    return best


def crop_for_word(img, box):
    """Largest 3:4 crop containing the word box, biased to center it."""
    W, H = img.size
    l, t, w, h = box
    aspect = OUT_W / OUT_H
    cw, ch = (int(H * aspect), H) if int(H * aspect) <= W else (W, int(W / aspect))
    if w > cw * 0.7 or h > ch * 0.25 or w < cw * 0.06:
        return None  # word too large/small relative to the frame
    cx = l + w // 2 - cw // 2
    cy = t + h // 2 - ch // 2
    cx = max(0, min(cx, W - cw))
    cy = max(0, min(cy, H - ch))
    # word must be fully inside
    if l < cx or t < cy or l + w > cx + cw or t + h > cy + ch:
        return None
    crop = img.crop((cx, cy, cx + cw, cy + ch)).resize((OUT_W, OUT_H), Image.LANCZOS)
    norm = ((l - cx) / cw, (t - cy) / ch, w / cw, h / ch)
    return crop, norm


def process_one(title, url, dictionary, used_counts):
    try:
        data = fetch(url)
        img = Image.open(io.BytesIO(data)).convert("RGB")
    except Exception:
        return None
    with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
        img.save(tmp.name)
        try:
            rows = ocr_words(tmp.name)
        except Exception:
            return None
    picked = pick_word(rows, dictionary, used_counts)
    if not picked:
        return None
    _, word, conf, box = picked
    result = crop_for_word(img, box)
    if not result:
        return None
    crop, norm = result
    return {"title": title, "word": word, "conf": conf, "image": crop, "box": norm}


def write_assets(slides):
    import shutil
    if ASSET_DIR.exists():
        shutil.rmtree(ASSET_DIR)
    (ASSET_DIR).mkdir(parents=True)
    (ASSET_DIR / "Contents.json").write_text(json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2))
    lines = [
        "// Generated by Data/tools/build_promo.py — do not edit by hand.",
        "import Foundation",
        "",
        "/// One promo slide: an artwork that visibly contains `word`, with the",
        "/// word's normalized bounding box for the highlight + lookup card.",
        "struct PromoSlideData: Identifiable {",
        "    let id: Int",
        "    let imageName: String",
        "    let word: String",
        "    let x: Double",
        "    let y: Double",
        "    let width: Double",
        "    let height: Double",
        "}",
        "",
        "enum PromoData {",
        "    static let slides: [PromoSlideData] = [",
    ]
    for i, slide in enumerate(slides):
        name = f"Promo{i + 1:03d}"
        imgset = ASSET_DIR / f"{name}.imageset"
        imgset.mkdir()
        slide["image"].save(imgset / f"{name}.jpg", "JPEG", quality=82, optimize=True)
        (imgset / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{name}.jpg", "idiom": "universal", "scale": "2x"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2))
        x, y, w, h = slide["box"]
        lines.append(
            f'        PromoSlideData(id: {i}, imageName: "{name}", word: "{slide["word"]}", '
            f"x: {x:.4f}, y: {y:.4f}, width: {w:.4f}, height: {h:.4f}),")
    lines += ["    ]", "}", ""]
    SWIFT_OUT.write_text("\n".join(lines))


def load_existing():
    """Reload previously accepted slides (minus curated-out words) so a
    top-up pass only has to find the remainder."""
    manifest_path = REPO / "Data" / "tools" / "promo_manifest.json"
    if not manifest_path.exists():
        return []
    slides = []
    for i, entry in enumerate(json.loads(manifest_path.read_text())):
        if entry["word"] in CURATED_OUT:
            continue
        name = f"Promo{i + 1:03d}"
        jpg = ASSET_DIR / f"{name}.imageset" / f"{name}.jpg"
        if not jpg.exists():
            continue
        img = Image.open(jpg).convert("RGB")
        slides.append({"title": entry["title"], "word": entry["word"],
                       "conf": entry["conf"], "image": img,
                       "box": tuple(entry["box"])})
    return slides


def main():
    global ROOT_CATS, BLACKLIST
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=100)
    parser.add_argument("--merge", action="store_true",
                        help="keep curated existing slides, harvest TOPUP_CATS for the rest")
    args = parser.parse_args()

    BLACKLIST |= CURATED_OUT
    existing = load_existing() if args.merge else []
    if args.merge:
        ROOT_CATS = TOPUP_CATS
        print(f"merge mode: keeping {len(existing)} curated slides")

    dictionary = Dict()
    print("Harvesting category members…")
    titles = harvest_titles()
    print(f"  {len(titles)} candidate files")
    urls = thumb_urls(titles)
    print(f"  {len(urls)} thumb urls")

    slides = list(existing)
    used_counts = {}
    for slide in slides:
        used_counts[slide["word"]] = used_counts.get(slide["word"], 0) + 1
    existing_titles = {s["title"] for s in slides}
    items = [(t, u) for t, u in urls.items() if t not in existing_titles]
    with futures.ThreadPoolExecutor(max_workers=8) as pool:
        pending = {pool.submit(process_one, t, u, dictionary, used_counts): t
                   for t, u in items}
        for future in futures.as_completed(pending):
            if len(slides) >= args.target:
                break
            result = future.result()
            if not result:
                continue
            word = result["word"]
            if used_counts.get(word, 0) >= MAX_WORD_REUSE:
                continue
            used_counts[word] = used_counts.get(word, 0) + 1
            slides.append(result)
            print(f"  [{len(slides):3d}] {word:<16} conf={result['conf']:.0f}  {result['title']}")

    slides = slides[:args.target]
    print(f"Accepted {len(slides)} slides; writing assets…")
    write_assets(slides)
    manifest = [{k: s[k] for k in ("title", "word", "conf", "box")} for s in slides]
    (REPO / "Data" / "tools" / "promo_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    print("Done.")


if __name__ == "__main__":
    main()
