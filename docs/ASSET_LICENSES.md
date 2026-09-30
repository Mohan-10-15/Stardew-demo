# ASSET LICENSES

Every art, audio and font asset imported into the project, with source URL and
license. CC0 assets do not require attribution; they are logged here for our own
record so the provenance of anything shipping is always traceable.

**Rule:** art stays within KayKit, Quaternius and Kenney.nl so the game reads as
one deliberate style rather than a grab-bag. A pack from outside these three
sources needs a decision entry in `docs/DECISIONS.md` first.

---

## Art

| Pack | Source URL | License | Imported to | Added |
|------|-----------|---------|-------------|-------|
| KayKit — Adventurers Character Pack 1.0 | `https://kaylousberg.itch.io/kaykit-adventurers` (mirror: `https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0`) | CC0 1.0 — `Assets/Art/KayKit/Adventurers/LICENSE.txt` | `Assets/Art/KayKit/Adventurers/` | 2026-09-30 |
| Quaternius — Farm Buildings Pack (Sep 2018) | `https://quaternius.com/packs/farmbuildings.html` (pack page: `https://quaternius.itch.io/lowpoly-farm-buildings`) | CC0 1.0 — `Assets/Art/Quaternius/FarmBuildings/LICENSE-CC0.txt` | `Assets/Art/Quaternius/FarmBuildings/` | 2026-09-30 |

Both packs are CC0, so no attribution is required in-game. Both licence files ship
inside the imported folders as the authoritative copy.

### What landed

| Source | Contents | Prefabs |
|--------|----------|---------|
| KayKit Adventurers | 5 rigged characters, 27 accessories, 76 animation clips per character | `Assets/Prefabs/Characters/KayKit_Adventurer_*.prefab` (5), `Assets/Prefabs/Props/AdventurerAccessories/KayKit_Accessory_*.prefab` (27) |
| Quaternius Farm Buildings | 13 buildings and props | `Assets/Prefabs/Props/FarmBuildings/Quaternius_Farm_*.prefab` (13) |

Only the FBX files were imported from the archives. Quaternius also ships OBJ and
Blend copies, which were deliberately skipped: Unity reads FBX natively, the OBJ
copies carry no material assignment, and the Blend files are Blender sources this
project does not open.

Characters are normalised to **1.800 m** tall with the pivot at the feet by
`EmberHollow.EditorTools.ArtPackImporter.Build`, so a 1-unit farm tile and a
character are consistent. All 45 prefabs share 85 materials under
`Assets/Art/Materials/{KayKit,Quaternius}/`, each on `Universal Render Pipeline/Lit`
with GPU instancing enabled — no magenta, no per-instance materials.

## Audio

| Asset | Source URL | License | Notes |
|-------|-----------|---------|-------|
| — | — | — | M7 audio pass. Not yet sourced. |

Audio will be original or CC0. Nothing will be taken from a commercial asset
library without a license record here.

## Fonts

| Font | Source URL | License | Notes |
|------|-----------|---------|-------|
| — | — | — | M0 HUD pixel font, task T-0104. |

Pixel fonts will be open-licensed (SIL OFL or CC0) so the WebGL build can embed
the file without a licensing question.

---

## Legacy assets

The previous TypeScript/Vite build generated all of its textures procedurally at
runtime and shipped no binary art. Nothing to log. See
`docs/legacy-web/AGENTS-web.md`.
