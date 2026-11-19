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
- **Backgrounds are procedural shaders**, not paintings: ordering art from ChatGPT in the built-in browser was blocked
  in this session's auto mode. Six animated styles (crystals, sunken temple with caustics, dunes at sunset, forest at
  night, lava forge, nebula), each with its own ambient particles.
- **Android package kept as `com.maxsoft.bejeweled`** (the existing Google Play app), version 2.0.0 (code 20000,
  above the live Cordova 1.1.0 / code 10001). The Play AAB is signed with the same key as the old Cordova app.
- **Music:** a Suno track was generated for the game (2 takes), but downloading needs the owner's last Suno download
  credit, so a CC0 track ships until the owner approves.
