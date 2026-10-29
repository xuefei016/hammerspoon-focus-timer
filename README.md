# Hammerspoon Focus Timer

A single-file Pomodoro timer for [Hammerspoon](https://www.hammerspoon.org/) that only counts time when you are actually working.
It looks at the frontmost app (and the current browser tab) and runs/pauses the clock against your own whitelist and blacklist — plus daily work statistics in the menu bar.

Built and used daily on macOS 26/27. Chinese comments in the source; this README is bilingual.

```
💻 24:31        working (whitelisted app in front)
💻⏸ 24:31       paused (blacklisted / unknown / idle)
☕ 04:12        short break
☕ 19:40        long break
💻⏸❓ 25:00     ❓ = the current app/site is in neither list
```

## Features

- **Pomodoro cycle** — work / short break / long break, long break every N pomodoros (default 25 / 5 / 20 / every 4). All durations are configurable from the menu, no code editing.
- **Whitelist / blacklist aware** — apps matched by bundle id (with name fallback), websites matched by domain with longest-match precedence (so `google.com` can be blacklisted while `mail.google.com` stays whitelisted).
- **Settle delay** — switching apps does not pause/start instantly; the new classification must hold for `settleSeconds` (default 60) before it takes effect. A quick glance at WeChat won't break your session.
- **Idle detection** — no keyboard/mouse input for `idleSeconds` (default 180) pauses the clock.
- **Extend when you're not done** — `⏰ 延长时间` adds 5/10/15 min, or pulls you back out of a break and continues working.
- **Manual classification** — `🏷 归类当前前台目标…` opens a small panel: whitelist / blacklist. Manual-only, no nagging notifications.
- **Daily statistics** — effective work / real break / paused time and completed pomodoros today and for the last 7 days, persisted to disk.
- **Optional focus mode** — toggle macOS Focus through two Shortcuts you create yourself.
- **Optional break ticking** — a soft tick every second while on a break so you notice you're resting.
- **Screenshots-free & permission-light** — no Accessibility, Screen Recording or notification permissions are required for the core features.

## Install

Requirements: macOS + [Hammerspoon](https://www.hammerspoon.org/) 1.0+.

```bash
git clone https://github.com/xuefei016/hammerspoon-focus-timer.git
# if you don't have a config yet:
cp hammerspoon-focus-timer/init.lua ~/.hammerspoon/init.lua
```

If you already have `~/.hammerspoon/init.lua`, don't overwrite it — load this file from your own config instead:

```lua
dofile(os.getenv("HOME") .. "/path/to/hammerspoon-focus-timer/init.lua")
```

Then reload: Hammerspoon menu → **Reload Config**, and the ticking clock appears in the menu bar.

## Configure

Everything lives in the `cfg` table at the top of `init.lua`.

**Whitelist / blacklist apps.** Bundle id is the reliable way:

```bash
mdls -name kMDItemCFBundleIdentifier -raw /Applications/Visual\ Studio\ Code.app
# com.microsoft.VSCode
```

```lua
workAppIDs  = { ["com.microsoft.VSCode"] = true },
blockAppIDs = { ["com.tencent.xinWeChat"] = true },
workApps  = { "Terminal" },   -- name fallback, used when bundle id is unavailable
```

**Websites** — subdomains match automatically:

```lua
domains      = { "github.com", "stackoverflow.com", "localhost" },
blockDomains = { "youtube.com", "x.com" },
```

**Behaviour knobs**

| key | default | meaning |
|---|---|---|
| `workSeconds` / `breakSeconds` / `longBreakSeconds` | 25 / 5 / 20 min | cycle lengths (also editable in the menu) |
| `pomodorosBeforeLongBreak` | 4 | every N pomodoros → long break |
| `settleSeconds` | 60 | how long a new classification must hold before it changes the clock (0 = instant) |
| `idleSeconds` | 180 | idle time that pauses the clock |
| `unknownPolicy` | `"pause"` | what to do when the frontmost thing is in neither list: `"pause"` or `"keep"` (keep the previous state) |
| `breakTick` | `true` | tick once per second during breaks |
| `extensionMinutes` | `{5,10,15}` | choices offered by “extend” |
| `focusModeEnabled` | `false` | run two Shortcuts when work starts/stops |
| `mergeAgedIntoSource` | `false` | where yesterday's classifications get folded into permanent lists (see below) |

## Data files

All state is written next to your config (`~/.hammerspoon/`):

| file | content |
|---|---|
| `focus-stats.json` | per-day work / rest / paused seconds + completed pomodoros |
| `focus-settings.json` | the settings you changed from the menu |
| `focus-list-overrides.json` | classifications made **today** — undoable from `🏷 我归的类` |
| `focus-lists-merged.json` | classifications from previous days, folded into the permanent lists automatically |

Yesterday's manual classifications are folded into `focus-lists-merged.json` at the first launch of a new day (or at midnight), so the override file never grows without bound. If you prefer them written straight into `init.lua`, set `mergeAgedIntoSource = true` — it syntax-checks the result before writing and keeps `init.lua.bak-*` backups (last 5).

## Optional sounds

macOS system sounds are used by default (`Hero`, `Funk`, `Tink`). To use your own, drop audio files into `~/.hammerspoon/sounds/` and reference them by filename:

```lua
sounds = { autoWork = "alert-work.mp3", tick = "tick.mp3" },
```

Any `.mp3` / `.wav` works. [Pomotroid](https://github.com/Splode/pomotroid) (MIT) has a nice set at `static/audio/` — no audio files are bundled in this repo.

## Tests

The classification/scheduling logic is testable without Hammerspoon:

```bash
brew install lua
lua test.lua        # 38 checks: precedence, longest-match, settle delay, long-break cadence, undo
```

## 中文速览

- 菜单栏一个计时器：**只有前台是你白名单里的 App / 网站时才计时**，黑名单和未知目标暂停，切个微信不会被立刻打断（默认要离开 60 秒才算数）。
- 番茄节奏（工作/短休/长休/每几个长休）和延长时长都能在菜单 `⏱ 番茄节奏` 里点选，不用改代码。
- 想归类当前 App 或网站：菜单 `🏷 归类当前前台目标…`，只有手动触发，不会弹通知打扰。菜单栏出现 `❓` 就代表当前这个目标还没归类。
- 当天归的可以在 `🏷 我归的类` 里逐条撤销；隔天的会自动沉淀成永久名单，覆盖文件不会越滚越长。
- 统计写在 `~/.hammerspoon/focus-stats.json`，菜单里能看今日和最近 7 天。

## License

MIT — see [LICENSE](LICENSE). Not affiliated with the Hammerspoon project.
