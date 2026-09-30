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
| — | — | — | — | — |

_KayKit, Quaternius and Kenney packs are added by task T-0101; each is logged here
with its source URL on the day it lands._

### Intended sources

| Pack | Purpose | Source |
|------|---------|--------|
| KayKit — character pack | Rigged, animated player and NPCs | `kaylousberg.itch.io` |
| Quaternius — Farm Buildings | Buildings, fences, farm structures | `quaternius.itch.io` |
| Quaternius — Nature | Trees, rocks, bushes, ground clutter | `quaternius.itch.io` |
| Quaternius — Farm Animals | Animated animals | `quaternius.itch.io` |
| Kenney.nl | Supplementary props, UI, icons | `kenney.nl` |

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
