# M3 Contracts — people (schedules, dialogue, gifts, friendship, events, quests, journal)

Status: ratified by ORCHESTRATOR. Workers code against this document; raise
disagreements in their report (`DONE T-#### | files | verify | issues`).

Read first: AGENTS.md, docs/ARCHITECTURE.md, src/core/contracts/m1-contracts.md,
src/core/contracts/m2-contracts.md, this doc. All M1/M2 contracts stay in force.

## 0. New content kinds (core, already landed — T-0300)

The orchestrator added three Zod-validated content kinds + loaders + cross-ref
validation to src/core (schemas.ts, content.ts), plus time helpers in
src/core/time.ts. Workers READ these; nobody edits them.

- `content/schedules.json` (keyed by npcId): `{ home: mapId, homeAnchor?,
  default: ScheduleRule[], overrides: [{ when?, rules }] }` where
  `ScheduleRule = { from, to, map, x, y }` with game-minutes in the Stardew
  scale 600..2700 (6:00 = 600, 2:00 = 2600) and `when` = any subset of
  `{ season 0..3, weather, day 1..28, dayOfWeek }`.
  - Types: `NpcScheduleDef`, `ScheduleRule`, `ScheduleOverride` (core/schemas).
  - Hazard: schedule maps/tiles are validated to exist; REACHABILITY of
    schedule tiles is authored, not enforced (deferred to M6 validator).
- `content/dialogue.json` (keyed by npcId): line pools `default` (required),
  optional `byHeart` ("0".."10"), `weather`, `season` ("0".."3"), `time`
  (`morning|day|evening|night`), `giftReply {loves,likes,neutral,dislikes,hates}`,
  `eventLine { eventId: lines }`, and `heartEvents [{ id, hearts, map?, time?,
  line, reward {hearts?, items?} }]`. Type: `DialogueDef`.
- `content/quests.json` (keyed by questId): `{ name, giver (npcId), description,
  objective: {type:'collect',item,count?} | {type:'deliver',item,to} |
  {type:'talk',to}, reward {gold?, items?, hearts?[{npc,amount}]}, repeats:
  'once'|'weekly' }`. Types: `QuestDef`, `QuestObjective`.
- Time helpers (core/time.ts): `clockToGameMinutes(clock)` -> 600..2600,
  `dayIndex(calendar)`, `dayOfWeek(calendar)` (0=Sunday), `dayOfWeekName`.
  DayOfWeek keys in content: `sunday..saturday`.

## 1. Where state lives

- NPC positions: `state.maps[mapId].npcs[npcId] = { npcId, x, y, facing }`
  (core `MapState.npcs`, already typed). The people:sim owns these writes.
- People/quest runtime state: `state.extensions.people`:
  ```
  {
    targets: Record<npcId, { mapId, x, y }>,      // current intents
    eventsPlayed: string[],                        // heart-event ids, once each
    quests: Record<questId, { prog: number, done: boolean }>
  }
  ```
  JSON-safe, saved with the rest of state automatically.
- Inventory/money/relationships live where M1/M2 put them; the people sim may
  MUTATE `state.player.money`, `state.player.inventory`, and
  `state.relationships` inside its reducers (ShippingSim/ShopSim are the
  precedent), always reusing read-only helpers from
  `src/features/inventory/sim/InventorySim` (`addStackToInventory`,
  `summarizeInventory`) — importing to USE is fine; editing those files is not.

## 2. Schedules + movement (WORKER-3)

- `resolveSchedule(def, ctx) -> { mapId, x, y }` pure function where ctx =
  `{ seasonIndex, weather, dayOfMonth, dayOfWeek, gameMinutes }`:
  1. Choose the FIRST override whose `when` matches (missing field = wildcard);
     else the `default` rules.
  2. Choose the LAST rule with `from <= gameMinutes < to`; if no rule covers,
     return `home` + `homeAnchor` (or the home map's authored spawn).
- Each `time:tick` (10-min), people:sim advances every NPC:
  - target = resolveSchedule(def, today's ctx).
  - If target.mapId != NPC's current map: INSTANT map change — remove from old
    map's npcs, place at target tile on the new map (a "walked through a door"
    cut; authors put cross-map windows at night). Same-map: walk tile-by-tile.
  - Walk deterministically: compute an A* path from current tile to target tile
    over walkable tiles (legend `walkable === true`), tie-break by examining
    directions in order N, S, W, E and preferring lower f-cost. Move up to
    `NPC_WALK_TILES_PER_TICK = 3` tiles per tick; set `facing` per step; at the
    goal stop and face down. NPCs may not enter the player's tile or an NPC'd
    tile (blocked -> just don't move that step).
  - A path is computed once per target change; keep it so replays are identical.
- Stations/waiting: when at the target tile, the NPC stays (facing down).

## 3. Dialogue (WORKER-3)

- Interact (`player:interact` on an NPC tile, bare hand) -> `people:talk`.
- Say text = `pickDialogue(def, ctx, rng)` (pure), ctx = `{ hearts, weather,
  seasonIndex, gameMinutes, giftJustGiven }`. Pool precedence:
  `byHeart` (highest tier with hearts >= tier) > `weather` > `season` >
  `time` (morning <1200, day 1200..<1800, evening 1800..<2400, night >=2400)
  > `default`. When `giftJustGiven`, use `giftReply` by taste instead.
- Random pick within a pool uses `rng.fork('dialogue:' + npcId + '@' + dayCount)`
  so the same day always says the same line. “Say something else” cycles the
  pool with the next seeded index.
- Talking counts once per day: `relationship[npcId].talkedToday = true`,
  hearts += 0.25 (clamp 0..10). Emit `friendship:changed { npcId, hearts,
  delta: 0.25, taste: 'talk' }`.
- Emit `dialogue:show { npcId, lines: string[] }`; WORKER-3's dialogue UI renders
  it with an avatar chip (initials on a colored disc from baseProfile.color).

## 4. Gifts + friendship (WORKER-3)

- Interact with an NPC tile while HOLDING an item -> `people:gift { npcId,
  itemId }`. Consumes 1 of the item from inventory (first stack of that id).
- Taste from `npcDef.gift` lists; first gift of the day counts
  (`giftCountToday`): delta loved +1, like +0.5, neutral +0, dislike -0.5,
  hate -1; clamp 0..10. Emit `friendship:changed { npcId, hearts, delta,
  taste }`; UI shows the matching `giftReply` line.
- Hearts = relationship.hearts (0.25 increments allowed; hearts display is
  floor()).

## 5. Heart events (WORKER-3)

- Trigger check runs after `people:talk` (and after gift replies): pick the
  first heartEvent (content order) with `hearts <= relationship.hearts`,
  `ev.map` matches the player's map (or unset), current gameMinutes inside
  `ev.time` (or unset), and id not in `extensions.people.eventsPlayed`.
- On trigger: emit `people:event { npcId, eventId, phase: 'start' }`, then one
  `dialogue:show` with the lines of `eventLine[ev.line]`; player advances lines
  (`people:event-step`). On the final step apply reward: hearts cap at 10,
  items via `addStackToInventory` (full inventory -> gold replacement at
  item.price.base, emit `event:dropped`), push id to eventsPlayed, emit
  `people:event { phase: 'end' }`.
- While an event is playing, WORLD input is locked (input:ui gate — same
  mechanism M1 uses; the player can only advance the event).

## 6. Quests (WORKER-3)

- Board/giver: any NPC whose schedule keeps it still in town (e.g. a `board`
  role NPC authored in npcs.json with a standing schedule) lists its quests.
  Available set for giver G = quests.json entries with `giver === G` and
  (`repeats === 'weekly'`, seeded daily rotation capped at 3) or
  (`repeats === 'once'` and not in `active`/`completed`). Emit
  `quests:board { giver, list: questId[] }`.
- `quests:accept { questId }`: push to `quests.active`; init
  `extensions.people.quests[id] = { prog: 0, done: false }`; emit
  `quests:updated`.
- Progress is implicit from state (no per-quest ticks):
  - collect: `prog = countItem(inventory, item)` (re-evaluated at turn-in or on
    each quests:refresh), `done = prog >= count`.
  - deliver `{ item, to }`: interact with NPC `to` while holding `item` and the
    quest is active -> consume 1 item, `done = true`.
  - talk `{ to }`: interact with NPC `to` -> `done = true`.
- `quests:turn-in { questId }`: only on the giver's NPC tile while `done`.
  Apply reward (gold -> money, items -> inventory, hearts -> relationships),
  move id to `completed`, drop from `active`, delete prog entry. Emit
  `quests:updated` + `quests:completed { questId }`.
- Weekly quests reappear (same id can be accepted again after turn-in).

## 7. Journal UI (WORKER-3)

- Keymap action `journal` (data-driven, e.g. J) toggles the journal overlay.
- Tabs: Quests (active list + objective text + progress, completed list),
  People (hearts bar out of 10 per NPC; gift tastes shown as icon+text, hidden
  as "?" until that NPC has hearts >= 2), Skills (read-only current levels).
- All strings via the existing i18n helper; keyboard/gamepad friendly.

## 8. View rendering (WORKER-1)

- Render every NPC in `state.maps[currentMap].npcs` as a simple low-poly
  humanoid (tunic color + hair color from `npcDef.baseProfile` with sensible
  defaults), smooth-lerp position from the previous tick position over the 10
  min tick, bob while walking, face from `npc.facing`. Destroy/move them on
  `people:event start/end`? (No — only lock player input.) Hide all NPCs when
  the map has none or on `player:warped` -> rebuild from the new map's npcs.
- Keep the farm/village visuals from M2 untouched; no new assets required.

## 9. Supporting economy (WORKER-2)

- Add ~6 gift-friendly items to content/items.json (gems/universals:
  amethyst, emerald, topaz, opal, chocolate, rainbow-prism — loved/liked
  targets), all with asset-less categories (mineral/resource/crafted).
- Seasonal shop stock: `state.extensions.shop` gains
  `{ stock: ..., seasonStock: Record<shopId, Record<itemId, boolean>> }`
  filtered by an optional new per-stock-entry content field
  `season?: [0|1|2|3]` — core ShopDef change REQUIRED:
  report to orchestrator (orchestrator adds `season` to shopSchema when
  requested, before M3 lands).
- Traveling merchant: new shop content/shops/traveling-merchant.json, present
  ONLY on Fridays (dayOfWeek === 5) with a seeded rotating stock (rng fork
  'merchant@' + dayIndex); `shop:open` from the village map when the merchant
  is present. WORKER-2 owns this; expose availability via
  `extensions.shop.merchantToday` boolean.
  - NOTE: core schema change for `season` + merchant presence is
    orchestrator-owned; state clearly in the report if the gate blocks on it.

## 10. Tests (workers run only their lane)

- WORKER-3: tests/sim/people.test.ts (resolveSchedule precedence + cross-map
  + home fallback; A* determinism; pickDialogue precedence + seeded pick;
  gift deltas incl. cap/first-per-day + giftReply; heart-event trigger, reward,
  once-only; quest accept/progress/turn-in/reward + journal state).
  tests/sim/quests.test.ts optional split. Pure-function tests only.
- WORKER-1: extend view tests — NPCs in the scene mirror `state.maps[n].npcs`;
  rebuilding on `player:warped`.
- WORKER-2: shop.test.ts extension — seasonal stock + traveling merchant
  availability/rotation.
- Gate = full `npm run check` by ORCHESTRATOR (+ acceptance rows M3).

## 11. Content ownership for M3

- WORKER-3 authors: content/npcs.json (add 4-5 NPCs -> 6-7 total, gift tastes
  referencing EXISTING items or items WORKER-2 adds), content/schedules.json,
  content/dialogue.json, content/quests.json.
- WORKER-1 owns content/maps/* (may touch only if needed for event space: use
  existing maps; no new map required).
- WORKER-2 owns content/items.json + content/crops.json + content/shops/*.

## 12. Do NOT touch

src/core/* (unless reported per §9), docs/*, package.json, vite/eslint configs,
tests of other lanes, src/features of other lanes (importing to use is fine).
If a schema or core change is needed, say so in the report.

## 13. Dispatch order

- T-0301 WORKER-3 part A: schedules/pathfinding/dialogue/gifts/hearts + content
  (npcs/schedules/dialogue).
- T-0302 WORKER-1: NPC view rendering + warp rebuild.
- T-0304 WORKER-2: seasonal stock + traveling merchant + gift items.
- T-0303 WORKER-3 part B: heart events + quests + journal (after T-0301 lands,
  same worker).