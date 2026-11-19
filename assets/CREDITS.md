# Credits

## Sound effects (all CC0 / public domain — thank you!)

| File(s) in assets/audio | Source | Author | License |
|---|---|---|---|
| click, toggle, error*, hint, complete, lift, pluck*, drop_* | [Interface Sounds](https://opengameart.org/content/interface-sounds) | Kenney (kenney.nl) | CC0 |
| powerup, star, sparkle | [50 CC0 retro / synth SFX](https://opengameart.org/content/50-cc0-retro-synth-sfx) | rubberduck | CC0 |
| pop | [Bubbles pop](https://opengameart.org/content/bubbles-pop) | farfadet46 | CC0 |
| win_* | [Win jingle](https://opengameart.org/content/win-jingle) | Fupi | CC0 |
| swap, shuffle, special, prism_1, line_1, line_2, fail | [63 Digital sound effects](https://opengameart.org/content/63-digital-sound-effects-lasers-phasers-space-etc) | Kenney (kenney.nl) | CC0 |
| crack_*, stone_*, bomb_1, bell_* | [100 CC0 SFX](https://opengameart.org/content/100-cc0-sfx) | rubberduck | CC0 |
| bomb_2, line_3, prism_2 | [50 CC0 Sci-Fi SFX](https://opengameart.org/content/50-cc0-sci-fi-sfx) | rubberduck | CC0 |
| fw_* | [25 CC0 bang / firework SFX](https://opengameart.org/content/25-cc0-bang-firework-sfx) | rubberduck | CC0 |
| chime_0..9 | synthesized for this game by `tools/make_chimes.py` (pentatonic crystal bells) | — | CC0 |

## Music

`music.ogg` — "Crystal Cave (song18)" by cynicmusic, [OpenGameArt](https://opengameart.org/content/crystal-cave-song18), CC0.
An original Suno soundtrack "Gem Swap" was generated for the game (two takes in the owner's Suno library); `scripts/sfx.gd`
prefers `music.mp3` if it is added.

## Fonts

Nunito and Lobster — Google Fonts, SIL Open Font License 1.1 (`assets/fonts/OFL_*.txt`).

## Art

All gems (8 cuts + the prism) and the stone block are rendered in Blender Cycles by `blender/scripts/render_gems.py`
(8 light angles per gem for the glints). World backgrounds are procedural shaders (`shaders/background.gdshader`),
effects are code (`scripts/fx.gd`). App icon is composed from the gem renders by `tools/make_icon.py`.
