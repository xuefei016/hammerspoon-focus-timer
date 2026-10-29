-- 无依赖单测: stub 掉整个 hs.*, 直接跑 init.lua 里的判定逻辑
-- 用法: lua test.lua        (需 brew install lua)
-- 不会读写你真实的 ~/.hammerspoon

local TMP = "/tmp/hsfocus-test-" .. tostring(os.time())
os.execute("mkdir -p " .. TMP)

local front = {name_ = "code", bid_ = "com.microsoft.VSCode"}

local function appStub(n, b)
  return {name = function() return n end, bundleID = function() return b end}
end

hs = {
  configdir = TMP,
  json = {read = function() return nil end, write = function() return true end},
  timer = {
    secondsSinceEpoch = function() return _G.__now or os.time() end,
    doEvery = function(_, fn) _G.__tick = fn return {} end,
    doAfter = function() return {stop = function() end} end,
  },
  menubar = {new = function()
    return {setTitle = function(_, t) _G.__title = t end, setMenu = function() end}
  end},
  sound = {getByName = function() return nil end, getByFile = function() return nil end},
  task = {new = function() return nil end},
  alert = {show = function() end},
  host = {idleTime = function() return 0 end},
  osascript = {applescript = function() return false, nil end},
  application = {frontmostApplication = function() return appStub(front.name_, front.bid_) end,
                 runningApplications = function() return {} end},
  caffeinate = {
    watcher = {
      screensDidLock = 1, systemWillSleep = 2, sessionDidResignActive = 3,
      screensDidUnlock = 4, sessionDidBecomeActive = 5, systemDidWake = 6,
      new = function() return {start = function() end} end,
    },
  },
  reload = function() end,
  chooser = {new = function() return {placeholderText = function() end, choices = function() end, show = function() end, hide = function() end} end},
  notify = {new = function() return {send = function() return true end} end},
}

package.preload["hs.ipc"] = function() return {} end

dofile("init.lua")

local F = _G.FocusTimer
local fails, total = 0, 0

local function check(desc, got, want)
  total = total + 1
  if got ~= want then
    fails = fails + 1
    print(string.format("FAIL  %-46s got=%s want=%s", desc, tostring(got), tostring(want)))
  end
end

-- 造一小份名单来验判定(真实使用请写在 init.lua 的 cfg 里)
F.cfg.workAppIDs = {["com.microsoft.VSCode"] = true, ["com.apple.Terminal"] = true}
F.cfg.workApps   = {"Visual Studio Code"}
F.cfg.blockAppIDs = {["com.tencent.xinWeChat"] = true}
F.cfg.blockApps   = {"WeChat"}
F.cfg.domains      = {"github.com", "mail.google.com"}
F.cfg.blockDomains = {"youtube.com", "google.com"}

-- App 判定
check("白名单 bundle id", F.kindOfApp("Anything", "com.microsoft.VSCode"), "work")
check("白名单 名称兜底", F.kindOfApp("Visual Studio Code", ""), "work")
check("黑名单 bundle id", F.kindOfApp("WeChat", "com.tencent.xinWeChat"), "block")
check("黑优先于白", F.kindOfApp("WeChat", "com.microsoft.VSCode"), "block")
check("都没命中 = 未知", F.kindOfApp("Preview", "com.apple.Preview"), "unknown")

-- 网站判定(黑优先, 最长匹配)
check("白名单域名", F.kindOfHost("github.com"), "work")
check("白名单子域", F.kindOfHost("gist.github.com"), "work")
check("黑名单域名", F.kindOfHost("youtube.com"), "block")
check("最长匹配: mail.google.com 放白", F.kindOfHost("mail.google.com"), "work")
check("最长匹配: google.com 拉黑", F.kindOfHost("google.com"), "block")
check("后缀欺骗不算命中", F.kindOfHost("github.com.evil.com"), "unknown")

-- 长休息节奏
F.cfg.pomodorosBeforeLongBreak = 4
for i = 1, 8 do
  check(string.format("第 %d 个番茄 → 长休息=%s", i, tostring(i % 4 == 0)), F.isLongBreakAfter(i), i % 4 == 0)
end

-- decide 语义: pause 模式未知即暂停, keep 模式沿用上一次明确判定
F.cfg.idleSeconds = 100000
F.cfg.unknownPolicy = "pause"
check("pause: work", F.decide("work"), true)
check("pause: 未知即停", F.decide("unknown"), false)
F.cfg.unknownPolicy = "keep"
check("keep: work", F.decide("work"), true)
check("keep: 未知沿用 work(第1轮)", F.decide("unknown"), true)
check("keep: 未知沿用 work(第3轮)", (function() F.decide("unknown") return F.decide("unknown") end)(), true)
check("keep: block", F.decide("block"), false)
check("keep: 未知沿用 block", F.decide("unknown"), false)
F.cfg.unknownPolicy = "pause"

-- 结算延迟: 切换应用后要稳定 60 秒才改状态
_G.__now = os.time()
F.cfg.settleSeconds = 0
front.name_, front.bid_ = "Preview", "com.apple.Preview"
_G.__tick()
local function runningNow() return (tostring(_G.__title):find("⏸") == nil) end
check("暖机: 未知应暂停", runningNow(), false)

F.cfg.settleSeconds = 60
front.name_, front.bid_ = "Code", "com.microsoft.VSCode"
_G.__tick()
check("切到白名单: 立刻仍在暂停", runningNow(), false)
_G.__now = _G.__now + 30; _G.__tick()
check("切到白名单: 30 秒仍暂停", runningNow(), false)
_G.__now = _G.__now + 31; _G.__tick()
check("切到白名单: 61 秒开始计时", runningNow(), true)

front.name_, front.bid_ = "WeChat", "com.tencent.xinWeChat"
_G.__tick()
check("切到黑名单: 立刻仍在计时", runningNow(), true)
_G.__now = _G.__now + 31; _G.__tick()
check("切到黑名单: 31 秒仍计时", runningNow(), true)
_G.__now = _G.__now + 31; _G.__tick()
check("切到黑名单: 62 秒才暂停", runningNow(), false)

-- 菜单栏 ❓ 标识: 未知目标时出现
front.name_, front.bid_ = "Preview", "com.apple.Preview"
F.cfg.settleSeconds = 0
_G.__tick()
check("未知目标 → 标题带 ❓", (tostring(_G.__title):find("❓") ~= nil), true)
front.name_, front.bid_ = "Code", "com.microsoft.VSCode"
_G.__tick()
check("白名单 → 标题无 ❓", (tostring(_G.__title):find("❓") == nil), true)

-- 手动归类写盘 & 撤销
F.addTarget("block", {name = "Preview", bid = "com.apple.Preview"})
check("归类后判定变 block", F.kindOfApp("Preview", "com.apple.Preview"), "block")
check("归类记 1 个目标", F.overrideCount(), 1)
F.removeTargetAt(1)
check("撤销后回到原判定", F.kindOfApp("Preview", "com.apple.Preview"), "unknown")

os.execute("rm -rf " .. TMP)
print(string.format("\n%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
