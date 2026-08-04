# Voccab

A vocabulary study app for iPhone, rebuilt from a reference app with two
frontends sharing one backend:

- **VoccabClassic** (`Apps/Classic`) — a faithful visual copy of the original
  app (light + dark mode).
- **VoccabRedesign** (`Apps/Redesign`) — the same pages and function zoning
  with a completely redesigned visual language.
- **VocabKit** (`Packages/VocabKit`) — shared data + logic layer: dictionary,
  word lists, SRS scheduling, study sessions, CSV import, search.

## Upgrades over the original

- **Configurable recitation order** (the original could not set study order):
  Settings → Study → Study Order, plus a per-session override on the session
  start page. Orders: list order, frequency (common/rare first), familiarity
  (low/high first), planned review due-first, alphabetical A-Z/Z-A, random.
- **Selectable memory algorithms** (Settings → Study → Algorithm): the
  original's fixed Ebbinghaus ladder ("Memory Circles", default), Leitner
  boxes, SM-2, and a simplified FSRS-4.5 — all driven by the same
  I Know / I Don't Know input, switchable at any time without losing
  progress. Research notes in `docs/ALGORITHMS.md`.
- **Multi-dictionary word page** with per-dictionary toggles in Settings:
  English-Chinese (bundled, ECDICT), English definitions + Synonyms (bundled,
  WordNet), Apple system dictionary, and an Oxford slot that activates when
  licensed data is imported (not bundled for copyright reasons).

## Data

`Data/dict/voccab-dict.sqlite` is built by `Data/tools/build_dict.py` from:

- [ECDICT](https://github.com/skywind3000/ECDICT) (English→Chinese, word
  frequency ranks, exam tags, word forms)
- [WordNet 3.1](https://wordnet.princeton.edu/) (English definitions,
  examples, synonyms)
- A user-supplied Concise Oxford dump (31k entries), audited and loaded by
  `Data/tools/load_oxford.py` into the `oxford` table

`Data/seed/sat_rw_vocab.csv` seeds the starter "SAT RW Vocab" list on first
launch.

## Building

Requires macOS + Xcode 16. The generated `Voccab.xcodeproj` is committed, so
a plain download builds directly:

```sh
open Voccab.xcodeproj   # pick the VoccabClassic or VoccabRedesign scheme
```

After editing `project.yml`, regenerate with `xcodegen generate` (CI also
regenerates and commits the project automatically).

Unit tests: `swift test --package-path Packages/VocabKit`.

## CI visual loop

`.github/workflows/ios-visual-check.yml` builds both apps on a macOS runner,
runs XCUITest screenshot walkthroughs on an iPhone simulator (light + dark),
and force-pushes the PNGs to the `ci-screenshots` branch (also uploaded as a
workflow artifact) for review.
