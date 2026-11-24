# Audio review — Update 2, W6

Objective checks are automated (`tests/suites/test_music.gd`,
`tools/playtest_music.gd`). These are 17 original generative cues, rendered
from `resources/audio/cues/*.tres` by `MusicSynth` as stereo loops > 60 s with
bass, chord pad, melody, the five-note Heartstone leitmotif and a soft
percussion bed. No third-party audio file is used.

| Cue | Where it plays | Trigger to review | 👍/👎 | Notes |
|---|---|---|---|---|
| title | title screen | launch the game, stay on the menu | — | needs owner's ear |
| farm_spring / summer / autumn / winter | farm by season | New Game in each season (or set season via debug) | — | four arrangements of one theme |
| farm_night | farm after 20:00 | wait or advance the clock | — | lantern cue |
| village_day / village_night | village | walk to the square by day and by night | — | cottage glow |
| forest_edge | forest | walk to the forest road | — | — |
| pond | pond shore | walk to the pond | — | — |
| upper_mines / deep_mines | mine floors | enter the mine, descend to floor 3 then 8 | — | depth-tinted |
| combat | combat state | enter a fight in the mine | — | — |
| festival | festival day | attend Bloom Day | — | — |
| cutscene | cutscenes | play the intro | — | — |
| mending | The Mending | restore all six Embers at the plinth | — | leitmotif resolves here |
| credits | credits roll | finish the story | — | — |

## UX

A "Now playing" toast shows the cue title for 3 s when it changes (off via
`audio/now_playing_toast`). The jukebox opens on F6 and offers only cues the
player has already heard, tracked in `audio/jukebox_unlocked`; discovered cues
survive a config reload. `docs/evidence/update2/w6-jukebox.log` verifies the
unlock list and overlay in a window. Music frequency is Always / Often /
Sometimes — "Sometimes" doubles the ambience-only rest.

## Ambience

A location/season bed (wind, birds, crickets, pond, cave) plays under a weather
layer (rain, storm, snow), with periodic original one-shots (bird chirp,
cricket, cave drip) chosen by location. Four footstep surfaces now have three
recorded variants each plus pitch jitter. `tests/suites/test_ambience.gd` pins
the layer selection and that every id has a definition.

## Numeric listening substitute

Because there is no audible device, `tests/suites/test_audio_signal.gd` checks
the rendered waveform instead of the playback: all 17 cues are non-silent,
genuinely stereo, distinct from one another, below clipping, loop-bounded and
fade-seamed. A first draft of the seam assertion measured the full 20 ms fade
window and failed every cue — the correct property is that the *boundary
samples* are near zero, measured over 2 ms. That distinction is now documented
in the test. This proves the signal is well formed; it cannot prove the music
sounds good.

## Honest limits

- This machine has **no audible output device**. The windowed playtest verifies
  cue selection, streaming state (`playing=true`) and cue history, but the
  Music bus reports -200 dB. Audibility and taste are **human queue item 1**.
- The cues are generated in code (D23); their musical quality is bounded by the
  score data. The owner may mark each row 👍/👎 and the score `.tres` files can
  be edited without touching code.
