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
| Quaternius — Ultimate Nature Pack (Jun 2019) | `https://quaternius.com/packs/ultimatenature.html` (mirror: `https://opengameart.org/content/low-poly-nature-pack-1`) | CC0 1.0 — `assets/models/quaternius/NaturePack/LICENSE-CC0.txt` | `assets/models/quaternius/NaturePack/` | 2026-10-02 |

All three packs are CC0, so no attribution is required in-game. All licence files
ship inside the imported folders as the authoritative copy.

### What landed

| Source | Contents | Location |
|--------|----------|----------|
| KayKit Adventurers — characters | 5 rigged characters | `assets/models/kaykit/Characters/` |
| KayKit Adventurers — addons | 27 accessories and weapons | `assets/models/kaykit/Addons/` |
| Quaternius Farm Buildings | 13 buildings and props | `assets/models/quaternius/FarmBuildings/` |
| Quaternius Ultimate Nature | 29 of 150 models — trees, stumps, logs, bushes, berry bushes, rocks, crops, small plants | `assets/models/quaternius/NaturePack/` |

74 FBX total. Only the FBX files came across; Quaternius also ships OBJ and
Blend copies, which were skipped because Godot reads FBX natively and the OBJ
copies carry no material assignment.

The Nature Pack is the first pack to land **curated** rather than wholesale:
121 of its 150 models are dead/snow/autumn variants and extra variants of assets
already imported, so only the models with a use in content were copied. The rest
remain available from the source URL above if a variant is ever needed.

### Import notes

- Textures sit **next to** the FBX files that reference them. Godot resolves
  material texture paths relative to the mesh, so splitting them into a shared
  `textures/` folder produced untextured magenta meshes.
- The Nature Pack has **no textures at all** — Quaternius ships it flat-shaded
  with colour baked into the mesh, which is why it matches the buildings pack
  without any material work.
- Godot generates one `.import` file per FBX. Those are tracked; the compiled
  `.scn` cache under `.godot/imported/` is not.
- **Scale is reconciled for Quaternius; it is still open for KayKit.**
  - Quaternius: both packs author in centimetres, and Godot's FBX importer
    applies the centimetre-to-metre conversion itself, so imported models are
    already in metres with the pivot on the ground. Measured with
    `tools/probe_model_sizes.gd`, which writes
    `resources/nature/model_sizes.json`: a `BirchTree_1` is 3.57 m tall and a
    `Corn_1` is 1.98 m tall, and every model's `min_y` is within 0.2 of zero, so
    no vertical correction is needed. This supersedes the old "scale is not yet
    reconciled" note below for the Quaternius packs.
  - KayKit: still at the author's native scale. The Unity editor pass
    (`EmberHollow.EditorTools.ArtPackImporter.Build`) that normalised characters
    to 1.800 m with the pivot at the feet did not survive the move to Godot, so
    the character models still need a scale/pivot pass before they can be
    compared against a farm tile.
- **Measurement traps, for whoever writes more measurement tools.** Reading model
  bounds during a `--script` run's `_initialize()` reports pre-conversion values
  — a 357 m birch tree — because the importer's scale and Z-up axis fix-up live
  in the node transform and the tree is not live yet. Measure on a deferred
  frame with the instance parented under `root`. Also note that `AABB` is a value
  type in GDScript: passing one into a recursive walk and assigning to it
  discards the result silently.
- No material or lighting setup exists yet. Terrain is still procedural; the
  Nature Pack models are the first CC0 assets actually referenced by a scene.

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
