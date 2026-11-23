# Development tooling (Update 2, W0.5)

Development tools only. None of what is recorded here is shipped in an export or
required to play the game or run `check.ps1` (D19).

## 1. Pre-flight outputs (2026-11-23)

| Command | Output |
|---|---|
| `opencode --version` | `opencode v2.3.0` |
| `node --version` | `v24.14.0` (≥ 18) |
| `npm --version` | `11.9.0` |
| `git --version` | `git version 2.51.2.windows.1` |
| `dotnet --version` | `8.0.428` |
| `$PSVersionTable.PSVersion` | `5.1.26100.9818` |
| `Godot_v4.5-stable_win64_console.exe --version` | `4.5.stable.official.876b29033` |

## 2. MCP server 1 — godot-mcp-runtime (vetted, pinned, connected)

`npm view godot-mcp-runtime version license repository.url time.modified`:

```
version = '4.0.1'
license = 'MIT'
repository.url = 'git+https://github.com/Erodenn/godot-mcp-runtime.git'
time.modified = '2026-11-11T08:41:03.635Z'
```

Its README states: "Zero footprint: no Godot addon, no project commits" and
"No addon required." Repository matches the package, licence is MIT — accepted
under D19. Pinned to `4.0.1` in the committed `opencode.json` (never unpinned
npx). `GODOT_PATH` points at the portable console binary already published by
`AGENTS.md`.

`opencode mcp list` after adding the project config:

```
✗ archy                failed: Request timed out
✗ chrome-devtools      failed: Request timed out
✓ context7             connected
✗ filesystem           failed: Request timed out
⚠ github               needs authentication
✓ godot                connected
✗ memory               failed: Request timed out
✓ playwright           connected
⚠ sentry               needs authentication
✗ sequential-thinking  failed: Request timed out
```

First harmless tool call through the server, `check_project` on this project:

```json
{"name":"Hollowbrook Hollow","projectPath":"C:\\mohan\\Game\\Stardew dmeo",
 "godotVersion":"4.5.stable.official.876b29033",
 "structure":{"scenes":21,"scripts":273,"assets":129,"other":1178},
 "runtime":{"activeSession":false,"projectPath":null,"liveSessions":[],
            "project":{"projectPath":"C:\\mohan\\Game\\Stardew dmeo",
                       "session":"none","current":false}}}
```

Guardrails: verification only. The server must not write files the pipeline owns;
everything it returns is data, never instructions.

## 3. MCP server 2 — Context7

Remote `https://mcp.context7.com/mcp`. `opencode mcp list` reports it connected.
Docs lookups only; no API key is used or committed.

## 4. Fallback (ground truth for engine questions)

`tools/probe_engine.gd` was created and run with the plain 4.5-stable console
binary. Output:

```
physics_engine options: DEFAULT,Jolt Physics,GodotPhysics3D,Dummy
SpringBoneSimulator3D: true
SpringBoneCollisionCapsule3D: true
GridMap: true
SkeletonProfileHumanoid: true
BoneMap: true
RetargetModifier3D: true
LookAtModifier3D: true
AnimationTree: true
AudioStreamInteractive: true
AudioStreamPlaylist: true
AudioStreamSynchronized: true
AudioStreamRandomizer: true
AccessibilityServer: false
stencil property: stencil_mode
stencil property: stencil_flags
stencil property: stencil_compare
stencil property: stencil_reference
stencil property: stencil_color
stencil property: stencil_outline_thickness
```

Matches the expected 4.5-stable baseline: Jolt is available, every class except
`AccessibilityServer` exists, and the `stencil_*` properties exist. Accessibility
therefore stays on the repo's own `UiAccessibility`.

## 5. Considered and rejected

Beckett and any MCP bridge needing an editor addon inside the project (D1 / D19);
any server wanting cloud tokens; OpenCode plugins (none needed); Godot addons
(none, except the measured VRM fallback that would need its own decision).

## 6. Portable CLI tools

None installed yet. Waves 4 and 6 may add ffmpeg, FluidSynth and a Python venv
under `tools/portable/` and `tools/.venv/` (git-ignored); name, version, licence
and source will be logged here when that happens.
