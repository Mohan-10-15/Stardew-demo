# Asset Licenses

Goal: CO0/permissive only. Log every external asset family actually used here.

- **Kenney** (CC0) — target for UI icons, tools, furniture, plant sprites.
- **Quaternius** (CC0) — target for low-poly props, rocks, plants, characters.
- **Poly Pizza / Quaternius packs** (CC0) — target for buildings, decor.
- **OpenGameArt CC0** — fallback for any gap (trees, fences, water normal).
- Music/SFX: WebAudio-synthesized (owned) or CC0 loops (Selfish Gene, Eric
  Matyas et al. on OpenGameArt). Any used CC0 track gets attributed here.

Asset pipeline rule (WORKER-1): all art access goes through an **asset-ID
layer** (e.g. `asset: "tree-oak"`) so any asset can be swapped without code
changes. Assets fetched and placed under `public/assets/` — log the source
URL + license line here when that happens.

Nothing is imported yet as of M0.

- **Silkscreen** (SIL Open Font License 1.1, free) — used for the UI pixel
  font. Loaded from Google Fonts
  (https://fonts.googleapis.com/css2?family=Silkscreen:wght@400;700), applied
  via src/style.css. Vendor: Jason Kottke contributor "TypeSetit", OFL 1.1;
  no attribution required beyond retaining the license text, preserved in the
  OFL declaration.