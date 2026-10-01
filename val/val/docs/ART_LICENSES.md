# Asset Licenses

Every art, audio and font asset in the project, with source URL and license.
CC0 assets do not require attribution; they are logged here so the provenance
of anything shipping is always traceable.

**Rule:** art stays within KayKit and Quaternius so the game reads as one
deliberate style. A pack from outside these sources needs a decision entry in
`DECISIONS.md` first.

All paths are `res://` paths relative to the Godot project root.

---

## Art

| Pack | Source URL | License | Location | Added |
|------|-----------|---------|----------|-------|
| KayKit — Adventurers Character Pack 1.0 | `https://kaylousberg.itch.io/kaykit-adventurers` (mirror: `https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0`) | CC0 1.0 — `assets/models/kaykit/LICENSE.txt` | `assets/models/kaykit/` | 2026-09-30 (Unity), re-landed in Godot 2026-10-01 |
| Quaternius — Farm Buildings Pack (Sep 2018) | `https://quaternius.com/packs/farmbuildings.html` (pack page: `https://quaternius.itch.io/lowpoly-farm-buildings`) | CC0 1.0 — `assets/models/quaternius/LICENSE-CC0.txt` | `assets/models/quaternius/FarmBuildings/` | 2026-09-30 (Unity), re-landed in Godot 2026-10-01 |

Both packs are CC0, so no attribution is required in-game. Both licence files
ship inside the imported folders as the authoritative copy.

### What landed

| Source | Contents | Location |
|--------|----------|----------|
| KayKit Adventurers — characters | 5 rigged characters | `assets/models/kaykit/Characters/` |
| KayKit Adventurers — addons | 27 accessories and weapons | `assets/models/kaykit/Addons/` |
| Quaternius Farm Buildings | 13 buildings and props | `assets/models/quaternius/FarmBuildings/` |

45 FBX total. Only the FBX files came across; Quaternius also ships OBJ and
Blend copies, which were skipped because Godot reads FBX natively and the OBJ
copies carry no material assignment.

### Import notes

- Textures sit **next to** the FBX files that reference them. Godot resolves
  material texture paths relative to the mesh, so splitting them into a shared
  `textures/` folder produced untextured magenta meshes.
- Godot generates one `.import` file per FBX. Those are tracked; the compiled
  `.scn` cache under `.godot/imported/` is not.
- **Scale is not yet reconciled.** In Unity the characters were normalised to
  1.800 m tall with the pivot at the feet by
  `EmberHollow.EditorTools.ArtPackImporter.Build`, a Unity-only script that did
  not survive the move to Godot. The raw FBX files here are at KayKit's and
  Quaternius's native scale, so a character will not match a farm tile until a
  scale/pivot pass is written. Treat this as the first task of the art pipeline
  group, not as a done item.
- No material or lighting setup exists yet. The Godot world is still built from
  procedural meshes and a procedural sky; the CC0 packs are staged and licensed,
  not yet in use by any scene.

## Audio

| Asset | Source URL | License | Notes |
|-------|-----------|---------|-------|
| — | — | — | Not yet sourced. |

Audio will be original or CC0. Nothing will be taken from a commercial asset
library without a licence record here.

## Fonts

| Font | Source URL | License | Notes |
|------|-----------|---------|-------|
| — | — | — | Not yet sourced. |

Fonts will be open-licensed (SIL OFL or CC0) so an exported build can embed the
file without a licensing question.

## Procedural art

Everything the game currently renders — terrain, props, characters, the player —
is generated at runtime by `scripts/world/world_builder.gd` from primitives and
noise. That work is original and carries no third-party licence. It is the
fallback, and the reference for what the CC0 packs must beat.
