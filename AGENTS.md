# AGENTS.md — Gem Swap

Match-3 puzzle in Godot 4.7 (2D, GL Compatibility): swap Blender-rendered gems, make specials and cascades,
60 levels in 6 worlds + endless bonus levels + Blitz 90 s. Remake of the old HTML/Cordova "Gem Swap"
(removed from this folder; see `decisions.md`).

## Where everything is

| What | Where |
|---|---|
| Project | `C:\My-progs\Godot\gemswap` |
| GitHub (public) | https://github.com/msveshnikov/gem-swap (remote `origin`, branch `master`) |
| Live web build | https://severance.lol/9/ = https://maxims.top/gems/ (server symlink `/var/www/maxims/gems -> /var/www/severance/9`) |
| Android APK | https://severance.lol/9/GemSwap.apk — signed with `~/.android/debug.keystore` |
| Server folder | `ubuntu@severance.lol:/var/www/severance/9/` (SSH key auth) |
| Google Play | app "Gem Swap: Match 3 Jewels", package `com.maxsoft.bejeweled`, Play Console app id 4972699497167054865 (dev 5957945224586801272). Before the remake: Cordova 1.1.0 (code 10001) live. 2.0.0 (code 20000) + new en-US listing + ru-RU translation sent for review 2026-11-19; 2.1.0 (code 20100, backgrounds + music + phone layout) the same day |
| Play upload key | `~/.android/gemswap-upload.jks` (alias `my-key-alias`, password in `gemswap-upload.txt`) = the old Cordova key with key password = store password. Godot reads it from `.godot/export_credentials.cfg` (preset.3). Never commit. Original Cordova keystore: `~/.android/gemswap-cordova.keystore` + `.txt`. |
| Godot exe | `C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe` |
| Blender exe | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` |
| Gem sprites | `blender/scripts/render_gems.py` → `assets/gems/*.png` (strips of 8 light angles, 192 px) |
| Levels | `assets/levels/levels.json` ← `python tools/gen_levels.py`, then `-- --calibrate` tunes moves + stars |
| Icon / splash | `python tools/make_icon.py` (from the gem renders) |
| Match chimes | `python tools/make_chimes.py` |
| Sounds, music, fonts | `assets/audio`, `assets/fonts` — sources and licences in `assets/CREDITS.md` |
| Music | `assets/audio/music.mp3` = Suno "Gem Swap" https://suno.com/song/714a3a8c-cda5-47aa-af08-c68dff92a2a8 (downloaded; alt take b1634bdb… not) |
| Backgrounds | ChatGPT paintings: prompts `art/bg_prompts.json`, originals `art/bg_raw/*.png` (1024x1536) → `python tools/make_backgrounds.py` → `assets/bg/*.jpg`; after the first `--import`, `python tools/make_backgrounds.py --patch-import` (lossy WebP + mipmaps) and `--import` again |
| Save file | `user://save.json` (Windows: `%APPDATA%\Godot\app_userdata\Gem Swap\`) |
| Builds | `build/windows/GemSwap.exe`, `build/web/`, `build/android/GemSwap.apk`, `build/play/GemSwap.aab` |

## Code map

| File | Role |
|---|---|
| `scripts/game.gd` (autoload `Game`) | gems, worlds, levels, save, texts (ru/en), command-line flags |
| `scripts/sfx.gd` (autoload `Sfx`) | sound groups, music |
| `scripts/match3.gd` | pure rules: grid, matches, specials + combos, ice, stones, gravity, moves, shuffle |
| `scripts/sim.gd` | goal bookkeeping + greedy autoplayer (calibration) |
| `scripts/board.gd` | playfield: tiles, gems, ice, stones, input (swipe or tap-tap), every animation, hints, bonus finale |
| `scripts/gem.gd` | one gem: sprite strip glints, select pulse, land squash, pop, special-gem effects |
| `scripts/fx.gd` | shards, sparkles, beams, shockwaves, lightning, floating text, confetti, fireworks |
| `scripts/main.gd` | screens (title, world map, game HUD, start/win/lose/pause/settings), Blitz, autotest, calibration, store shots |
| `scripts/ui_kit.gd` | fonts, buttons, vector icons, stars, panels, gem icons |
| `shaders/background.gdshader` | six procedural world backdrops (fallback + under the paintings); `shaders/bg_image.gdshader` painted backgrounds; `shaders/gem.gdshader` flash / shine / rainbow |

## Rules

Swap two neighbours to line up 3+. 4 in a row → Line gem (clears its row or column), L/T → Bomb (radius-2 diamond),
5 → Prism (swap with a gem: clears that colour; with a special: turns that colour into specials). Special + special
swaps combo. Ice breaks when a gem on it is cleared; stones break from matches next to them or blasts.
Goals: score / collect / ice / stone. Leftover moves turn into line gems that fire (bonus). Stars: score thresholds in
the level (`stars`), set by calibration.

## Test

```
G="/c/Users/msves/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe"
"$G" --headless --path . --import
"$G" --path . --quit-after 40000 -- --autotest                       # portrait
"$G" --path . --resolution 1280x720 --quit-after 40000 -- --autotest # landscape (land_*.png)
"$G" --path . --resolution 360x800 --quit-after 40000 -- --autotest  # narrow phone (corner buttons, popups)
```
Logic tests (specials, gravity, prism, ice/stones, every level starts with moves), then every screen is shot into
`renders/game/`, a real drag swap, a refused tap swap, line/bomb/prism combos, win, lose, stones, Blitz.
Always check the last line of `renders/autotest.log`: `AUTOTEST DONE fails=0` (a script compile error can still exit 0).
Other flags: `-- --level N`, `-- --fresh`, `-- --unlock`, `-- --lang en|ru`, `-- --seed N`.

## Rebuild assets

```
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P blender/scripts/render_gems.py   # ~12 min
python tools/gen_levels.py && "$G" --headless --path . -- --calibrate --runs 24                                       # ~15 min
python tools/make_icon.py
```

## Build and deploy

```
"$G" --headless --path . --export-release "Windows Desktop" build/windows/GemSwap.exe
"$G" --headless --path . --export-release "Web" build/web/index.html
"$G" --headless --path . --export-debug "Android" build/android/GemSwap.apk
"$G" --headless --path . --export-release "Android Play" build/play/GemSwap.aab
scp -o BatchMode=yes build/web/* build/android/GemSwap.apk store/privacy.html ubuntu@severance.lol:/var/www/severance/9/
curl -sI https://severance.lol/9/index.pck
```
Bump `version/code` + `version/name` in BOTH Android presets for every release. Keep MSAA off (Mali driver leak).
GitHub release: `"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y.Z build/windows/GemSwap.exe build/android/GemSwap.apk --target master --title "Gem Swap X.Y.Z" --notes-file notes.md`.

## Google Play

Store art: `python tools/play_store.py` → `renders/play/` (icon, ru/en feature graphics, 7+7 phone screenshots).
Texts: `store/listing.md`. Privacy policy: https://maxims.top/gems/privacy.html.
Upload from the built-in browser: serve the repo with a local CORS server on 127.0.0.1 and set the page's
`input[type=file]` from a fetched blob (see the Magic Bottles / Hot Bag project memory for the snippet).
Release flow: Тестирование и выпуск → Рабочая версия → Создать выпуск → upload AAB → notes → Далее → Сохранить →
Обзор публикации (pre-check ~15 min) → Отправить на проверку.
