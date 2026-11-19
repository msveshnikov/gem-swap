# Decisions (made without asking)

- **Full remake in Godot 4.7, 2D.** The old game was a single HTML/Cordova page: an 8x8 grid of emoji, swipe to swap,
  matches of 3, no levels, no goals. The Cordova project (`www/`, `platforms/`, `res/`, `config.xml`, `package*.json`)
  was removed after the remake, as the owner asked. Its release keystore was backed up first to
  `~/.android/gemswap-cordova.keystore` (+ `.txt`).
- **Gems are real renders, not emoji.** Blender Cycles renders 8 differently-cut gems (each colour has its own shape,
  so the game stays readable for colour-blind players) and a rainbow Prism, each in 8 light angles. The game flicks
  through the angles for glints, selected gems keep turning in the light.
- **Original match-3 rules** (genre-standard, no copy of any specific game): match 4 → Line gem (clears a row or
  column), L/T → Bomb (diamond blast, radius 2), 5 → Prism (swap with a gem to clear its colour). Every pair of specials
  has its own combo (cross, 3x3 lines, mega bomb, colour → specials, board wipe).
- **Levels with goals:** score, collect gems, break ice (1–2 layers), smash stones (1–2 hits). 6 worlds × 10 levels,
  then endless bonus levels (late levels with new seeds and shuffled gem kinds). New gem kinds arrive with the worlds
  (Star Diamond in world 2, Fire Topaz in 3, Rose Heart in 4) with a "New gem!" intro.
- **Move counts and star thresholds come from an autoplayer** (`-- --calibrate`): a greedy bot plays each level 24×,
  moves are tuned to a target win rate that slowly drops from 85 % to ~55 %, stars = 45th/85th percentile of the
  bot's winning scores.
- **Leftover moves become a bonus finale** (line gems that fire one after another), so finishing early always pays.
- **+5 moves once per level** on the "out of moves" screen (free, no ads).
- **Blitz 90 s** mode with a best score; big cascades add a second.
- **Backgrounds are paintings from ChatGPT** (2.1.0): 6 worlds × 8 scenes + title + Blitz panorama, ordered in the
  built-in browser from `art/bg_prompts.json` (the middle of each picture is kept calm for the board). Level k of a
  world uses scene k % 8. Portrait screens crop to cover; wide screens show the whole painting over a blurred copy
  (`shaders/bg_image.gdshader`), with a slow drift and a cross-fade. The procedural shader stays underneath as the
  fallback and for its ambient particles. In 2.0.0 the backgrounds were procedural only, because ordering art was
  blocked in that session's auto mode.
- **Android package kept as `com.maxsoft.bejeweled`** (the existing Google Play app), version 2.0.0 (code 20000,
  above the live Cordova 1.1.0 / code 10001), then 2.1.0 (code 20100). The Play AAB is signed with the same key as the old Cordova app.
- **Music:** the original Suno track "Gem Swap" (take 714a3a8c…, the owner spent their last download credit on it) is
  `assets/audio/music.mp3`; the CC0 track from 2.0.0 was removed.
- **Phones:** the UI root is inset by the display safe area (cutout, rounded corners) on Android, corner buttons sit
  30+ px from the edges, and `_place()` writes anchor-relative offsets so a stale size on the first web/Android frames
  cannot push a button off screen; the screen is rebuilt 120 ms after the last resize.
