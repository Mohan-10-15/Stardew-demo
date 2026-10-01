# Hollowbrook Hollow

A stylized 3D farming and life-simulation game in the spirit of Stardew Valley —
an original world, cast and story. Restore the Heartstone by completing the
Valley Collections: crops, fish, minerals, recipes, critters and friendships.

Built with **Godot 4.5** and plain **GDScript**. No addons, no C#, nothing
installed system-wide.

## Play it

```powershell
# Play
& "val/val/tools/Godot_v4.5-stable_win64.exe" --path "val/val"

# Open in the editor
& "val/val/tools/Godot_v4.5-stable_win64.exe" --editor --path "val/val"
```

The Godot binary ships inside the repo at `val/val/tools/` and is git-ignored.

## Validate it

```powershell
pwsh -File val/val/tools/check.ps1
```

Runs the full pipeline — a clean project import, the automated test suite, and a
headless boot of the real main scene — and exits non-zero if anything fails or
if the engine logs a script error.

Current state: **92/92 tests passing**, import clean, boot clean.

## Layout

| Path | What |
|---|---|
| `AGENTS.md` | team rulebook: how to build and verify, architecture rules, lanes |
| `val/val/` | the Godot project |
| `val/val/docs/` | design document, licences, salvaged design notes |

## Docs

- [`AGENTS.md`](AGENTS.md) — team rules, lanes, quality gates
- [`val/val/README.md`](val/val/README.md) — controls, layout, architecture
- [`val/val/docs/GDD.md`](val/val/docs/GDD.md) — game design document
- [`val/val/DEVELOPMENT_STATUS.md`](val/val/DEVELOPMENT_STATUS.md) — what is built, what was tested, what is next
- [`val/val/docs/ART_LICENSES.md`](val/val/docs/ART_LICENSES.md) — every asset with source URL and licence