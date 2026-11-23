# Cast sheet (Update 2, W4)

Generated from `resources/npc/profiles/*.tres` and the shipped `NpcData`
descriptions. Route C (D21): anime-styled KayKit rigs with distinct silhouettes
and palettes — **not** twelve unrelated anime models.

| Villager | Build | Head | Hair | Eyes | Palette | Voice | Signature prop |
|---|---|---|---|---|---|---|---|
| Mira | average | 1.22 | long braid, auburn | blue | teal / cream / rust | 1.06 | seed pouch |
| Bram | broad | 1.12 | short tousled, dark brown | brown | leather / sand / slate | 0.78 | hammer |
| Fen | slim | 1.26 | ponytail, black | violet | night / lavender / wheat | 1.12 | firewood |
| Odette | average | 1.30 | long wavy, silver | sky blue | blue / ice / lilac | 1.18 | almanac |
| Sable | broad | 1.14 | bob, chestnut | amber | oak / linen / moss | 0.86 | fence post |
| Aurel | tall | 1.10 | swept, gold | blue | ochre / cream / navy | 0.92 | ledger |
| Lyra | slim | 1.28 | twin tails, rose | gold | rose / cream / sage | 1.24 | flute |
| Cassia | short | 1.34 | long straight, plum | violet | violet / lilac / olive | 1.08 | notes |
| Elke | slim | 1.30 | short curly, copper | green | green / cream / copper | 1.16 | watering can |
| Garrick | tall | 1.08 | bald + beard, brown | red | stone / linen / rust | 0.70 | shield |
| Halda | short | 1.24 | bun, silver | olive | grey / ivory / olive | 1.02 | story book |
| Dorian | broad | 1.18 | short neat, navy | gold | navy / linen / brick | 0.96 | travel bag |
| Player | average | 1.20 | short messy, brown | teal | green / cream / rust | 1.00 | hoe |

## Status

Profiles, colours, builds and activity→clip mapping are authored and tested
(`test_cast.gd`). The clips exist in the shared rig library (76 embedded clips,
`tools/probe_rig.gd`). `NpcAnimator` is a tested mapping layer; wiring it into
the live `Npc._animate` loop through an `AnimationTree` blend is still open, so
the in-game motion remains the original procedural bone posing for now. This is
recorded as a gap, not claimed as done.
