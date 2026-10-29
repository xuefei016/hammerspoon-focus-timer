# Optional alert sounds

The timer uses macOS system sounds by default (`Hero`, `Funk`, `Tink`), so **no files are needed here**.

To use your own, put audio files in this folder (`~/.hammerspoon/sounds/`) and reference them by filename in `cfg.sounds`:

```lua
sounds = {
  manualWork = "Hero",              -- system sound
  autoWork   = "alert-work.mp3",    -- file from this folder
  rest       = "Funk",
  longRest   = "Funk",
  tick       = "tick.mp3"
}
```

Any `.mp3` / `.wav` works — names containing an extension are loaded with `hs.sound.getByFile`.

Good source of freely licensed chimes: [Pomotroid](https://github.com/Splode/pomotroid) (`static/audio/`) — MIT licensed. Audio files are intentionally not bundled here.

Notes:

- `tick` is played once per second while on a break; keep it short (a few hundred ms).
- `soundRepeat` / `soundGap` in `cfg` control repeated playback (useful for a more prominent “break is over” chime).
- Volume is relative to your system output volume (`soundVolume`, `tickVolume`).
