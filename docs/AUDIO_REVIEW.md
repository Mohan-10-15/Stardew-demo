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

## Honest limits

- This machine has **no audible output device**. The windowed playtest verifies
  cue selection, streaming state (`playing=true`) and cue history, but the
  Music bus reports -200 dB. Audibility and taste are **human queue item 1**.
- The cues are generated in code (D23); their musical quality is bounded by the
  score data. The owner may mark each row 👍/👎 and the score `.tres` files can
  be edited without touching code.
