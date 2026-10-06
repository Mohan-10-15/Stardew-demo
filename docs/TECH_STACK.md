# Tech stack

Everything the project runs on, the exact versions present on this machine, and
the one command that validates all of it.

---

## Engine

| | |
|---|---|
| Engine | **Godot 4.5-stable** |
| Renderer | Forward+ (`config/features` carries `"Forward Plus"`) |
| Primary binary | `tools/Godot_v4.5-stable_mono_win64_console.exe` — .NET build, `v4.5.stable.mono.official.876b29033` |
| Fallback binary | `tools/Godot_v4.5-stable_win64_console.exe` — plain GDScript-only build, kept so the suite runs without .NET |
| Installed system-wide? | **No.** Both are portable copies in `tools/`, git-ignored. `godot` is not on `PATH`. |
| Console variant | The `console` binaries are used deliberately: they keep a stdout handle on Windows so `check.ps1` can redirect and scan for `SCRIPT ERROR`. |

If a binary is missing, re-download Godot 4.5-stable and drop it in `tools/`.
Do not add an installer.

## Language and framework

| | |
|---|---|
| Default language | **GDScript** — every system but one |
| Also enabled | **C#** (`net8.0`) — one system, `scripts/sim/BalanceSweep.cs` |
| Framework | Godot's own `Node` / `Resource` types. **No addons.** |
| Boundary rules | `docs/MULTI_LANGUAGE_ARCHITECTURE.md` — read before adding a cross-language call |

C# version notes: `LangVersion` 12.0, `Nullable` disabled, `TreatWarningsAsErrors`
false, `EnableDynamicLoading` true (Godot's requirement for `AssemblyLoadContext`
hot reload).

## .NET toolchain

| | |
|---|---|
| SDK | .NET SDK **8.0.425** (`dotnet --version`) |
| Project file | `Hollowbrook.csproj` at the repo root |
| Sdk | `Godot.NET.Sdk/4.5.0` |
| NuGet sources | `nuget.config`: local `tools/GodotSharp/Tools` **first**, then nuget.org |
| Build output | `.godot/mono/temp/bin/Debug/Hollowbrook.dll` (git-ignored) |
| Why a local NuGet source | The Godot .NET distribution ships its own SDK packages. Feeding from there makes a restore work with no network, which is what a headless box needs. |

Restore and build by hand:

```powershell
dotnet build Hollowbrook.csproj -v minimal --nologo
```

## Shell

This machine has **Windows PowerShell 5.1 only** — there is no `pwsh` (PowerShell 7).

```powershell
# 5.1 form (what this machine has):
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1

# 7 form (works where pwsh exists):
pwsh -File tools/check.ps1
```

`tools/check.ps1` itself is 5.1-compatible. Useful flags: `-SkipImport` while
iterating, `-TimeoutSeconds N` if a stage needs longer.

## Validation pipeline

`tools/check.ps1` runs four stages, each under a hard timeout, and exits non-zero
if any fails. Order matters — see `docs/MULTI_LANGUAGE_ARCHITECTURE.md` §2.

| Stage | Proves |
|---|---|
| `csharp` | `dotnet build` is clean — catches a compile error in a `.cs` file |
| `import` | the whole project rescans with zero parse/compile errors, and registers C# `[GlobalClass]` types against the freshly built DLL |
| `tests` | the automated suite passes, with a real pass/fail count |
| `boot` | the real main scene launches headlessly and reaches a playable state |

A stage that exits 0 while logging `SCRIPT ERROR` on stderr is treated as failed;
the script scans stderr as well as the exit code for exactly that reason.

## Other tooling

| | |
|---|---|
| Python | 3.12.5 — available, not required by the pipeline |
| Node | **not used**. No `package.json`, no bundler, no `node_modules` (see `AGENTS.md` §9) |
| Unity | retired and uninstalled (`AGENTS.md` §9) |
| Version control | git; `AGENTS.md` §3 covers who commits |

## Reproducible numbers

Everything the docs quote was measured with:

```powershell
# World / perf profile (quoted in MULTI_LANGUAGE_ARCHITECTURE.md §3)
& "tools\Godot_v4.5-stable_mono_win64_console.exe" --headless --path . --script res://tools/profile_boot.gd

# Test suite only, with counts
& "tools\Godot_v4.5-stable_mono_win64_console.exe" --headless --path . --script res://tests/run_tests.gd

# Boot check only
& "tools\Godot_v4.5-stable_mono_win64_console.exe" --headless --path . --script res://tools/boot_check.gd
```

**Quote every path argument.** The project folder is named `Stardew dmeo`, so an
unquoted `--path` truncates at the first space. `check.ps1` pre-quotes for this
reason.
