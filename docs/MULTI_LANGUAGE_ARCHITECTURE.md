# Multi-language architecture

Game: **Hollowbrook Hollow**, Godot 4.5-stable.

**GDScript is the default and will stay the default.** C# is enabled, is proven
to work end to end, and has exactly one system in it. This document records why
the boundary exists, what it costs, and the rules that keep it from spreading.

---

## 1. Why the project is multi-language at all

Three reasons, in this order:

1. **The brief asks for it.** The master prompt asks for a multi-language stack
   where a language change is justified by measurement, and explicitly forbids
   both "everything stays GDScript because that is what we know" and "we added
   native code because native code sounds fast". Enabling C# and then *not*
   using it until something earns it is the correct reading.
2. **`AGENTS.md` used to forbid C#.** The team rulebook's §5 said "no addons,
   no C#". That rule was written before the toolchain existed on this machine.
   It has been superseded for C# specifically — see `docs/DECISIONS.md` — and
   the rulebook's §5 now describes the stack that is actually in the repo.
3. **One system genuinely earns it.** The balance sweep (§4 below).

Nothing else in the project has earned a second language. Not the world build,
not the navigation grid, not the decoration scatter — the measurements are in
§3.

---

## 2. The toolchain

| Piece | What | Notes |
|---|---|---|
| Engine | `tools/Godot_v4.5-stable_mono_win64_console.exe` | .NET build of Godot 4.5-stable, portable, in-repo, git-ignored |
| Engine (fallback) | `tools/Godot_v4.5-stable_win64_console.exe` | The original GDScript-only build, kept so the suite runs without .NET |
| Project file | `Hollowbrook.csproj` | `Godot.NET.Sdk/4.5.0`, `net8.0`, `AssemblyName`/`RootNamespace` `Hollowbrook` |
| NuGet | `nuget.config` | Local feed `tools/GodotSharp/Tools` first, then nuget.org. The machine must not need the network for a build. |
| .NET SDK | 8.0.425 | Already installed; `dotnet --version` |
| CLI | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1` | Windows PowerShell 5.1 only; no `pwsh` 7 on this machine |

`tools/check.ps1` prefers the mono binary and falls back to the plain one, and
prints which one it picked. On the fallback engine the build stage is skipped
and any case that needs C# reports the system missing rather than silently
passing.

### Pipeline order — build, import, test, boot

This order is not arbitrary. Godot registers a C# `[GlobalClass]` by reflecting
over the **built** DLL during the import scan, so building after import would
leave `BalanceSweep` out of `.godot/global_script_class_cache.cfg` and GDScript
would not see it as a global class. Hence:

```
csharp  ->  import  ->  tests  ->  boot
```

---

## 3. The measurement that decided it

`tools/profile_boot.gd` times the three places that scale with world size:

```
[profile] world build + decoration scatter: 56.3 ms
[profile] NpcNavigation.build over 112x96 cells: 82.0 ms (9981 walkable, 771 blocked)
[profile] WorldBuilder.is_reserved x100000: 104.0 ms (1.04 us each, 3587 hits)
[profile] DecorationField._too_close x50000 vs 600 occupied: 586.3 ms (11.73 us each)
```

Run on 2026-10-06, headless, on this machine. Interpretation:

- **56 ms and 82 ms are one-off boot costs.** Neither is on a frame budget. A
  boundary crossing that saves 50% of 82 ms saves 41 ms, once, at startup.
- **`is_reserved` at 1.04 µs** is a handful of distance checks. It is called
  per placement candidate during boot, not per frame.
- **`_too_close` at 11.73 µs** is the slowest thing in the game by a wide
  margin, and it is still 0.2% of a 60 fps frame budget *per call*. It runs
  during the decoration scatter at boot.

**Conclusion, recorded so it can be overturned:** nothing in the world or
engine lane justifies a language boundary today. If a future system needs one,
it needs a profile line first, not an opinion.

Re-run the numbers with:

```powershell
& "tools\Godot_v4.5-stable_mono_win64_console.exe" --headless --path . --script res://tools/profile_boot.gd
```

---

## 4. The one C# system

`scripts/sim/BalanceSweep.cs` — a deterministic parameter sweep over the crop
and tool tables:

- input: **twelve flat arrays** and six integers (224 days, 28-day seasons,
  start gold, plot count);
- output: **one dictionary** containing, per planting strategy, the end balance,
  gross revenue, seed spend and the day each tool tier became affordable;
- inner shape: `days x strategies x plots` with a sort of pending harvests in
  the middle — a nested loop with a sort, which is the shape that does not cache
  in an interpreter.

It exists because it is a *balance model*, meant to be re-run whenever content
changes and on every test run, and because it answers a question a real
playthrough cannot: a player only ever exercises one strategy, so playing the
game cannot tell you whether the worst profitable crop still reaches the
copper gate.

The GDScript half is `scripts/sim/balance_report.gd`. It owns the content schema
(`CropData`, `ItemDefinition`, `Clock`) and knows nothing about loops; the C#
half owns the loops and knows nothing about `.tres` files.

### Boundary rules

These are the rules that keep a two-language project from becoming a
two-language mess. All of them are load-bearing.

1. **Flat data crosses; objects do not.** Twelve arrays in, one dictionary out,
   marshalled in a *single* call. Nothing is marshalled per frame, no
   `GodotObject` graph crosses, no callback goes the other way.
2. **The C# side never touches a scene.** `BalanceSweep` extends `Resource`,
   has no `_process`, no signals, no node. It is a function with a
   `GlobalClass` on it.
3. **The GDScript side never loops over game content in a hot path.** The
   wrapper builds the arrays once and hands them over.
4. **A measurement, written down, precedes every new cross-language call.**
   Put the number in this document before the code.
5. **The boundary must fail loudly.** `tests/suites/test_balance.gd`'s first
   case asserts the assembly is loadable and instantiable, with a message
   naming the command that fixes it. A silently-unloadable assembly would
   otherwise make every balance case trivially pass.
6. **Adding GDExtension requires the same evidence plus more.** GDExtension
   buys you C++ at the cost of a native build per platform, a compile step in
   the pipeline, and a binary that cannot be inspected by opening a file. None
   of that is worth it for a 82 ms boot cost. Revisit if and when a measurement
   shows an inner loop on the frame budget.

---

## 5. Two Godot traps, both hit, both fixed

Neither is obvious and both cost real time. They are here so the next person
does not pay for them again.

### Trap 1 — the assembly name is `application/config/name`, not the `.csproj`

Godot's `Path::get_csharp_project_name()` reads `dotnet/project/assembly_name`
and falls back to `application/config/name`. This project is called
**"Hollowbrook Hollow"**, so Godot went looking for a file literally named
`Hollowbrook Hollow.dll`, did not find it, and reported the unhelpful:

```
.NET: Failed to load project assembly
ERROR: Cannot instantiate C# script because the associated class could not be
found. Make sure the script exists and contains a class definition with a name
that matches the filename of the script exactly (it's case-sensitive).
```

The class name *did* match the filename. The bug was the space in the project
title. Fixed by pinning the setting in `project.godot`:

```ini
[dotnet]

project/assembly_name="Hollowbrook"
```

If C# ever silently stops loading, check this first — the error message points
at the wrong thing.

### Trap 2 — a `--script` entry point cannot name an autoload-dependent `class_name`

A `--script` file is compiled during startup, **before** the autoloads are
added to the root. Any `class_name` whose file mentions `Log` or `EventBus`
fails to compile *there*, while compiling perfectly well when `run_tests.gd`
loads it a frame later. This is why `tools/profile_boot.gd` does

```gdscript
var world_builder := load("res://scripts/world/world_builder.gd") as GDScript
world_builder.call("build", world, seed)
```

instead of `WorldBuilder.build(world, seed)`. It looks worse and is correct.
`AGENTS.md` §4 states this as a standing rule; it was written from this exact
failure.

---

## 6. What is deliberately *not* here

- **No `GodotSharp`-derived game code.** Nothing subclasses an editor type, no
  `GodotTools` reference, no editor plugin in C#.
- **No C++/GDExtension.** See §4 rule 6.
- **No C# in a scene.** No `.tscn` attaches a C# script; scenes are still
  generated by `tools/*.gd` per `AGENTS.md` §1.
- **No cross-language signals.** Everything cross-cutting goes through the
  GDScript `EventBus` autoload as before. `BalanceSweep` publishes nothing.
- **No `async`, no threads, no `Task`.** The sweep is synchronous and completes
  within a test frame.
