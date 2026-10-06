# Audio Guide

How sound is meant to work, and the rules an audio system must obey.

**Status: not implemented.** `assets/audio/` is empty, no `AudioManager` exists,
and `scripts/audio/` does not exist as a folder. This document is the contract
that `AudioManager` will be built against, written now so the design is fixed
before implementation starts forcing decisions on it. See `docs/ACCEPTANCE.md`
M14 for the criteria it has to satisfy.

Nothing in this document is a stub or a placeholder — it is a specification. The
first milestone that touches audio (M14) implements it; before that, there is
genuinely nothing here.

---

## 1. Principles

**Audio is mandatory.** `prompt.md` §24 does not treat it as polish to be added
at the end if time allows. Silence in every action is a missing feature.

**Every distinct outcome already has a distinct `EventBus` event — audio listens
to those, it does not get called from gameplay code.** `AGENTS.md` §4 requires
every interact-style action to publish a clearly distinct success event *and* a
clearly distinct failure event. That rule exists for the ear as much as the eye:
if planting and failing to plant publish different events, they can be given
different sounds without touching `FarmService`.

**The game must not crash when there is no audio device.** Initialization is
defensive: a missing bus, a failed stream load or an unavailable output device
degrades to silence with one warning, never to an error that stops boot.

**Licensing is part of shipping the asset.** CC0 / permissive audio or
generated-synthesized audio only, and every pack is logged in
`docs/ASSET_LICENSES.md` with source URL and licence, exactly like the model
packs. An unrecorded sound file is an unshippable sound file.

---

## 2. AudioManager

A manager, not a system: it holds no gameplay rules. It registers itself, reacts
to `EventBus`, and can be added or removed without editing anything it serves.

Spawned by `main.gd` alongside the other services (`QuestService`,
`EconomyService`, `FarmService`), so it participates in the boot sequence rather
than being a hidden autoload with its own lifetime. Look it up the way
`TimeService` is looked up — `AudioManager.find(start)` — never by a hard-coded
path from a system that does not own it.

Responsibilities:

- own the `AudioStreamPlayer` / `AudioStreamPlayer3D` instances and their pool
- map an `EventBus` signal to a sound, in one place
- own the music state machine (what is playing, what crossfades into what)
- own volume buses and persist them through `Config`
- expose `play_sfx(id)`, `play_ambience(id)`, `set_music(cue)` for the few
  callers that are not reacting to a signal

Responsibilities it does **not** have: deciding whether an action succeeded,
knowing what a crop is, or holding a reference to any gameplay service.

---

## 3. Music

`prompt.md` §24 names these cues:

| Cue | Driven by |
|---|---|
| title | game phase (menu) |
| farm | player location on the farm |
| village | player location in the village |
| forest | player location in the forest |
| beach | player location at the shore |
| mines | player location in the mine |
| combat | combat state |
| festival | festival in progress |
| cutscene | a cutscene playing |
| night | hour of day, crossfaded over the regional cue |
| weather variants | `WorldTime.weather`, layered rather than replacing the region |

**At least 12 music loops/variants in the finished project.** The list above is
11 *cues*; the twelfth comes from a weather or seasonal variant of one of them.
Counting eleven names and calling it done does not satisfy the requirement.

Region comes from where the player is, not from a hardcoded zone test in the
player script: locations are already data (`LocationRegistry`, `LocationData`),
so the mapping is content.

Crossfade rather than cut. A hard swap on crossing a location boundary is the
audio equivalent of teleporting an NPC.

---

## 4. Sound effects

The full list from `prompt.md` §24, grouped by who will fire them:

- **footsteps and ground** — walking, grass, wood, stone
- **farming** — hoe, watering, planting, harvesting, axe, pickaxe, scythe
- **fishing** — cast, bite, hook, land (success and failure distinct)
- **containers and UI** — inventory, UI, doors, chests, shops
- **people** — NPC interaction
- **combat** — attack, damage, enemy death
- **world** — weather, rain, thunder, animals, machines, cooking
- **progression** — level-up, quest completion, festival, cutscenes

Two rules from `AGENTS.md` bind every one of these:

1. Success and failure must sound different. A refused swing and an accepted
   swing are not the same sound at a different volume.
2. Two *different* actions must not share a sound. Farming, fishing, mining and
   combat each have their own success and their own failure; they may not all
   resolve to "generic positive blip".

---

## 5. Buses and settings

Five buses, plus master:

```
Master
├── Music
├── SFX
├── Ambient
└── UI
```

Settings required: master volume, music volume, SFX volume, ambient volume, UI
volume, and mute. All of them persist through `Config` (`user://config.cfg`)
like every other setting, and all of them are reachable from the settings screen
in M15 without code changes.

Muting on pause is required, and it must not fight the pause: `GameState` owns
pausing, so audio reacts to the phase rather than the player pressing Escape and
audio independently noticing.

---

## 6. Content is data

Sounds are `Resource` definitions under `resources/audio/`, looked up by id —
the same rule as items, crops, NPCs and quests. A new sound is a new `.tres`, not
a new `if`.

An audio definition carries at minimum: `id`, the stream, the bus it plays on,
volume trim, pitch range, and whether it is random-pitched (footsteps and
impacts should be, or they machine-gun).

---

## 7. Spatial audio

World sounds are `AudioStreamPlayer3D` attached at their source — a well that
sounds close when you stand at it. UI and music are non-positional.

The player is the listener. Nothing in gameplay code positions it.

---

## 8. Testing

Headlessly testable, and therefore required:

- the audio registry loads, ids are unique, every definition names a real bus
- every `EventBus` event that promises a sound has one, and no two distinct
  outcomes map to the same definition (the distinctness rule, asserted)
- settings round-trip through `Config`
- a boot with no audio device logs one warning and reaches `PLAYING`

Not testable headlessly, and therefore needs a playtest in a real window:
whether it *sounds* right, whether the crossfade is audible as a crossfade,
whether a footstep is in sync with the foot.

---

## 9. Acceptance

`docs/ACCEPTANCE.md` **M14** is the sign-off:

- every major action has audio: footsteps, tools, impacts, UI, ambience
- music and ambience change with time of day and weather
- volume settings work and persist
- audio is muted correctly on pause
