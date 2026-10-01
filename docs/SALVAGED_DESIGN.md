# Salvaged Design Notes

Reference material recovered from the retired Unity project (`unity/`) and the
retired TypeScript build (`src/`). **None of this is wired into the game.** It
is a specification for groups that have not been built yet, kept because it was
already designed and tested once and re-deriving it would be waste.

Godot is 3D and real-time; the Unity project was 3D and the TypeScript build was
2D grid-based. Take the **rules and edge cases**, not the coordinates.

---

## Calendar and clock (Group 5)

Source: `unity/Assets/Scripts/Core/GameClock.cs`, ported from `src/core/time.ts`.
26 EditMode tests covered it. The design below is the whole of it.

### The model

`Clock.Hour` is a display hour in `0..23`, where `6` means 6:00 AM. Times
before 6 AM only occur after midnight while the farmer stays awake.

Internally the clock converts to **absolute minutes measured from the 6:00 AM
day start**:

| Moment | Absolute minute |
|---|---|
| 6:00 AM (day start) | `0` |
| midnight | `1080` (`18 * 60`) |
| 2:00 AM (collapse) | `1200` (`(18 + PassOutHour) * 60`) |

`ToAbsoluteMinutes` is the whole trick: a display time under 6 AM belongs to
the *end* of the day, so it gets `+1080`; anything from 6 AM on gets `-360`.
Because the conversion is pure, the same input always yields the same output —
a headless bot and a real playthrough stay in lockstep.

### Constants

| Name | Value | Note |
|---|---|---|
| `TickMinutes` | `10` | one sim tick = 10 in-game minutes |
| `DayStartHour` | `6` | waking / passing out lands here |
| `DaysPerSeason` | `28` | so a season is exactly 4 weeks |
| `SeasonsPerYear` | `4` | |
| `PassOutHour` | `2` | 2:00 AM collapse |
| `DaysPerYear` | `112` | `DaysPerSeason * SeasonsPerYear` |

### Operations

- **`Advance(world, minutes)`** — moves forward, clamps at the collapse point,
  and rolls the calendar when it crosses midnight. Returns a transition
  describing what happened: `day_rolled`, `season_rolled`, `year_rolled`,
  `passed_out`, plus the new world.
- **`NextDayMorning(world)`** — jumps straight to the next 6:00 AM, bypassing
  the collapse clamp. Sleep and end-of-day use this; the calendar rules are
  identical to `Advance`.
- **`StartNewDay(world)`** — resets to 6:00 AM on the *same* day, keeping
  weather.
- **`AddMinutes(clock, minutes)`** — display-clock arithmetic that wraps at
  midnight.
- **`WeekOf(day_of_month)`** — `(day - 1) / 7`, zero-based, so `0..3`.
- **`DaysUntil(from, to)`** — signed whole days between two dates.
- **`DayIndex(calendar)`** — absolute 0-based day; day 1 of year 1 is `0`.
- **`DayOfWeek(calendar)`** — `DayIndex % 7`, `0 = Sunday`, kept non-negative.
- **`ToGameMinutes(clock)`** — schedule-friendly minutes where 6:00 AM is `600`,
  midnight is `2400` and 2:00 AM is `2600`, so authored NPC schedule windows
  stay **monotonic across midnight** instead of wrapping to zero.
- **`DescribeDate(world)`** — `"Year 1 Spring 4"`.

### The rollover bug worth not repeating

When rolling forward past midnight, the leftover minutes must be written as
`remaining + (DayStartHour * 60)` — *not* the raw overflow. Writing the raw
value puts the new morning at `00:00`, which `ToAbsoluteMinutes` reads back as
18:00 the previous day, so the very next tick rolls the day over again, forever.
This was a real bug in the Unity build.

### Weather weights per season

`Sun / Rain / Storm / Snow / Wind`:

| Season | Sun | Rain | Storm | Snow | Wind |
|---|---|---|---|---|---|
| Spring | 6 | 2 | 1 | 0 | 1 |
| Summer | 7 | 2 | 1 | 0 | 0 |
| Fall | 6 | 2 | 1 | 0 | 1 |
| Winter | 6 | 0 | 0 | 3 | 1 |

Winter trades rain for snow; summer is driest.

### Edge cases the old tests pinned down

Worth re-asserting, because each one was a bug at some point:

- 6:00 AM is absolute minute zero.
- Advancing at midnight rolls the day; advancing just before it does not.
- At 2:00 AM the farmer collapses *and* the day rolls.
- Advancing past 2:00 AM **clamps** at the collapse point.
- Once `passed_out` is set it stays set.
- The season rolls on day 29 (i.e. after day 28).
- The year rolls after winter ends.
- `NextDayMorning` works even from a late-night clock.
- `NextDayMorning` leaves the original world untouched — copy, then mutate.
- Weather and forecast survive the advance.
- A full day of 10-minute ticks advances exactly one day.
- `DayOfWeek` stays in range across a whole year.
- `ToGameMinutes` is monotonic across midnight.

### Signals the Godot `EventBus` already declares

`time_minute_changed`, `time_hour_changed`, `day_started`, `day_ended`,
`season_changed`, `year_changed`. The clock should publish these and nothing
else — no system should read the clock directly.

---

## Inventory (Group 10)

Source: `unity/Assets/Scripts/Core/InventorySim.cs`. 29 EditMode tests.

Rules that are easy to get wrong:

- Adding **merges** into a matching stack, but never across a **quality**
  difference. Silver is not Normal.
- A stack that overflows **splits across slots** rather than failing.
- A full bag accepts nothing and loses nothing — all-or-nothing.
- Removing takes the **lowest quality first**, so you consume Normal before
  Gold.
- Removing **empties** a slot rather than leaving a zero-count ghost.
- Unknown item ids return `0` and change nothing.
- Non-stackables cost one slot **per unit**.
- `MoveSlots` handles: swap two different items, merge matching stacks, move
  into an empty slot, no-op from an empty slot, no-op onto itself.
- Growing the bag keeps contents. **Shrinking refuses** if items would be lost,
  and succeeds when empty.
- Resizing pulls the selection index back into range.
- A summary merges by `(id, quality)` and ignores empty slots.
- Adding zero quantity is a no-op.
- A new bag contains the starter loadout and leaves **no null slot**.

---

## Farming (Group 9)

Source: `unity/Assets/Scripts/Core/FarmingSim.cs` (28 KB, the largest sim) and
`src/features/farming/sim/`. Covered by `FarmingSimTests.cs` — the single
biggest test file in the Unity project at 22 KB.

The pipeline the playable slice already proved end to end:
**till → plant → water → grow → harvest**, each step publishing a distinct
success event and a distinct failure event on the `EventBus`.

The Unity project shipped a genuinely playable version of this loop, so the
balance numbers in that file are worth reading before writing new ones.

---

## Other useful leftovers

- `Rng.cs` — deterministic RNG, the basis of seeded world generation. The Godot
  `WorldBuilder` already does seeded generation; keep that.
- `DailyTick.cs` — one tick = crop growth, withering and weather. The shape to
  copy when a `SimulationRunner` equivalent is needed.
- `MovementMath.cs` / `PlayerMovement.cs` — the Godot project has its own
  `PlayerMotion` and 23 passing tests, which is further along. Do not port.
- `FarmGrid.cs` — tile-to-world mapping. Worth reading for the grid layout
  convention.
- The 15 empty feature folders under `unity/Assets/Scripts/Features/` were
  scaffolding only — every one was empty. No content was lost there.

---

## What was deleted, and what it cost

| Removed | Was it needed? |
|---|---|
| `unity/` (4.36 GB, 992 tracked files) | Its design is captured above; its CC0 art was kept |
| `src/` TypeScript build | Superseded — richer on paper (fishing, mining, crafting, NPCs, quests, shops) but 2D grid-based and abandoned. Salvage the *rules*, not the code. |
| Unity Editor + Hub (~12.5 GB installed) | No — Godot ships portable in `tools/` |
| `dist/`, `artifacts/`, `node_modules/` | Build output and dependencies |

The Unity project's genuinely unique contribution was the **CC0 art packs**,
which were kept, and the **calendar/inventory design**, captured above. Its 189
EditMode and 17 PlayMode tests tested C# that no longer exists; the Godot
project's own suite is the live one.
