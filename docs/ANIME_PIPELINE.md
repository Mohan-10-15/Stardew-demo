# Anime pipeline (Update 2, W4)

How the cast is built. See D16 (original overlays) and D21 (Route C decision).

## Ground truth

`tools/probe_rig.gd` reports every shipped rig at 41 bones, 6 skins, 12–15
meshes and 76 embedded clips on a shared skeleton. The animation library is
therefore part of the asset pack, not a new dependency.

## Route

Route C — anime-styled KayKit:

1. The five rigs stay; twelve villagers get distinct silhouettes through
   per-profile bone scaling, head proportion, hair clumps, eye colour and a
   three-colour outfit palette.
2. Animation comes from the rig's own `AnimationPlayer` clips, selected by a
   data map from the activity string in each schedule.
3. Faces stay the original `AnimeFace` drawn overlay; `AnimeStyle` provides the
   cel ramp and outline.
4. Portraits are a transparent `SubViewport` framing head and shoulders.

## Honesty rule

This is styling on a shared rig, not twelve different anime models. The cast
sheet and the owner-facing report must say so. Any VRM route needs a new
decision with licence evidence (D18) and a removal plan.

## Clip vocabulary

Required activity strings from `resources/npc/schedules/*.tres` map to shipped
clips: idle → `Idle`/`Unarmed_Idle`, walk → `Walking_A`, work → `Use_Item`,
talk → `Interact`, sit → `Sit_Chair_Idle`, sleep → `Lie_Idle`, cheer → `Cheer`,
pick-up → `PickUp`. A test asserts every schedule activity has a mapping.
