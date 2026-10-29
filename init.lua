-- ==========================================
-- Hammerspoon Focus Timer
-- 番茄钟 + 工作时间统计 + 白/黑名单自动暂停
-- 作者: xuefei016  ·  MIT License
-- ==========================================
--
-- 放好之后在 Hammerspoon 控制台执行 hs.reload(), 菜单栏会出现计时。
-- 详细说明见 README.md。
-- ==========================================

local cfg = {
  -- ---------------- 番茄节奏 ----------------
  workSeconds = 25 * 60,             -- 工作
  breakSeconds = 5 * 60,             -- 短休息
  longBreakSeconds = 20 * 60,        -- 长休息
  pomodorosBeforeLongBreak = 4,      -- 完成 N 个番茄 → 一次长休息
  extensionMinutes = {5, 10, 15},    -- 到点想做完手头的事: 菜单可延长这么多分钟

  -- ---------------- 判定 ----------------
  idleSeconds = 180,                 -- 多久没键鼠输入算离开(暂停计时)
  settleSeconds = 60,                -- 切换应用后, 新分类要稳定多久才改计时状态
                                     -- (防止临时切一下微信就暂停; 0 = 立即生效)
  unknownPolicy = "pause",           -- 都不在名单里时: "pause" 暂停 / "keep" 保持上一刻状态

  -- ---------------- 白名单 App(前台在此 = 工作) ----------------
  -- 匹配 bundle id 最稳: 终端执行
  --   mdls -name kMDItemCFBundleIdentifier -raw /Applications/YourApp.app
  workAppIDs = {
    -- ["com.microsoft.VSCode"]  = true,
    -- ["com.jetbrains.goland"]  = true,
    -- ["com.apple.Terminal"]    = true,
  },
  workApps = {
    -- "Visual Studio Code", "GoLand", "Terminal",
  },

  -- ---------------- 黑名单 App(前台在此 = 暂停) ----------------
  blockAppIDs = {
    -- ["com.tencent.xinWeChat"] = true,
    -- ["com.tdesktop.Telegram"] = true,
  },
  blockApps = {
    -- "WeChat", "Telegram",
  },

  -- ---------------- 白/黑名单网站(仅在浏览器前台时生效) ----------------
  -- 子域名自动匹配; 黑白重叠时取最长匹配(所以 google.com 拉黑时 mail.google.com 仍可放白)
  domains = {
    -- "github.com", "stackoverflow.com", "localhost", "127.0.0.1",
  },
  blockDomains = {
    -- "youtube.com", "x.com", "netflix.com",
  },

  -- 能读当前网址的浏览器(Chromium 系用同一段 AppleScript; Firefox 不支持)
  chromiumBrowsers = {
    ["Google Chrome"]  = true,
    ["Microsoft Edge"] = true,
    ["Brave Browser"]  = true,
    ["Arc"]            = true,
    ["Chromium"]       = true,
    ["Vivaldi"]        = true
  },

  -- ---------------- 声音 ----------------
  -- 名字带 .mp3/.wav → 从 ~/.hammerspoon/<soundDir>/ 读; 否则用 macOS 系统提示音
  soundDir = "sounds",

  sounds = {
    manualWork = "Hero",    -- 手动点"立即开始工作"
    autoWork   = "Hero",    -- 休息→工作(想更醒目就放个更响的音频文件进来)
    rest       = "Funk",    -- 进入短休息
    longRest   = "Funk",    -- 进入长休息
    tick       = "Tink"     -- 休息中每秒滴答
  },

  soundVolume = 1.0,               -- 相对系统音量
  soundRepeat = {                  -- 连响次数
    manualWork = 1, autoWork = 1, rest = 1, longRest = 1, tick = 1
  },
  soundGap = 0.6,                  -- 连响间隔(秒)
  breakTick  = true,               -- 休息中每秒滴答(关掉就只在切换时响)
  tickVolume = 0.8,

  -- ---------------- macOS 专注模式(可选, 需自建"快捷指令") ----------------
  focusModeEnabled = false,        -- 打开前先在"快捷指令"里建好下面两个快捷指令
  focusOnShortcut = "开工作专注",
  focusOffShortcut = "关工作专注",

  -- ---------------- 其他 ----------------
  saveInterval = 15,               -- 统计落盘间隔(秒)
  panelTimeout = 30,               -- 归类面板没人理, 多少秒自动收起

  -- 隔天的归类怎么永久化:
  --   false = 写进 focus-lists-merged.json(推荐, 不动本文件)
  --   true  = 直接改写本文件里的名单(会留下 init.lua.bak-* 备份)
  mergeAgedIntoSource = false
}

-- ==========================================
-- 1. 状态
-- ==========================================

local settingsPath = hs.configdir .. "/focus-settings.json"
local settings = {}
local settingsFile = io.open(settingsPath, "r")
if settingsFile then
  settingsFile:close()
  settings = hs.json.read(settingsPath) or {}
end
if settings.unknownPolicy == "pause" or settings.unknownPolicy == "keep" then
  cfg.unknownPolicy = settings.unknownPolicy
end

-- 番茄节奏(菜单里可改, 存 focus-settings.json)
if type(settings.workMinutes) == "number" and settings.workMinutes > 0 then
  cfg.workSeconds = math.floor(settings.workMinutes * 60)
end
if type(settings.breakMinutes) == "number" and settings.breakMinutes > 0 then
  cfg.breakSeconds = math.floor(settings.breakMinutes * 60)
end
if type(settings.longBreakMinutes) == "number" and settings.longBreakMinutes > 0 then
  cfg.longBreakSeconds = math.floor(settings.longBreakMinutes * 60)
end
if type(settings.pomodorosBeforeLongBreak) == "number" and settings.pomodorosBeforeLongBreak > 0 then
  cfg.pomodorosBeforeLongBreak = math.floor(settings.pomodorosBeforeLongBreak)
end

-- ==========================================
-- 1b. 自动归类覆盖（由"归类当前目标"写入, 不改 init.lua 本体）
-- ==========================================

-- 文件结构(focus-list-overrides.json):
--   targets = { {kind="work"|"block", type="app"|"host", name=, bid=, host=, at=} }
-- 一个目标就一条记录(一个 App 不再算两条), 这样才能按目标显示和逐条撤销。
-- 只有手动归类(菜单栏 → 归类当前前台目标…)会写入这里; 不做任何主动提醒。

local overridePath = hs.configdir .. "/focus-list-overrides.json"
local overrides = {targets = {}}

-- init.lua 里的原始名单快照, 撤销时用来重建
local baseLists = {}

-- ⚠️ hs.json.read 对两个空数组会返回**同一个 Lua 表**(rawequal = true),
-- 逐条复制成独立数组, 避免以后加数组字段时两张表被悄悄共用。
local function asArray(t)
  local out = {}
  if type(t) == "table" then
    for _, v in ipairs(t) do table.insert(out, v) end
  end
  return out
end

do
  local data = {}

  local f = io.open(overridePath, "r")
  if f then
    f:close()
    data = hs.json.read(overridePath) or {}
  end

  if type(data) == "table" then
    overrides.targets = asArray(data.targets)

    -- 兼容旧版(按条目存数组)的文件: 一次性转成 targets
    local legacy = {
      {"workApps", "work", "name"}, {"blockApps", "block", "name"},
      {"workAppIDs", "work", "bid"}, {"blockAppIDs", "block", "bid"},
      {"workDomains", "work", "host"}, {"blockDomains", "block", "host"}
    }

    for _, m in ipairs(legacy) do
      if type(data[m[1]]) == "table" then
        for _, v in ipairs(data[m[1]]) do
          local tg = {kind = m[2], at = 0, name = "", bid = "", host = ""}
          tg[m[3]] = v
          tg.type = tg.host ~= "" and "host" or "app"
          table.insert(overrides.targets, tg)
        end
      end
    end

  end
end

local function targetKeyOf(tg)
  if tg.host and tg.host ~= "" then return "host:" .. tg.host end
  if tg.bid and tg.bid ~= "" then return "app:" .. tg.bid end
  return "app:" .. tostring(tg.name or "?")
end

local function targetLabelOf(tg)
  if tg.host and tg.host ~= "" then
    local n = (tg.name and tg.name ~= "") and tg.name or "浏览器"
    return n .. ": " .. tg.host
  end
  if tg.name and tg.name ~= "" then return tg.name end
  return tostring(tg.bid or "?")
end

local function saveOverrides()
  if not hs.json.write(overrides, overridePath, true, true) then
    print("Focus Timer: 归类覆盖保存失败")
  end
end

local function hasValue(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function removeValue(list, v)
  for i = #list, 1, -1 do
    if list[i] == v then table.remove(list, i) end
  end
end

-- 都是"目标"计数, 不是内部条目数
local function overriddenCount() return #overrides.targets end

-- init.lua 基础名单里对这个目标是怎么归的("work"/"block"/nil)
local function baseSideOf(tg)
  if tg.host and tg.host ~= "" then
    if hasValue(baseLists.blockDomains, tg.host) then return "block" end
    if hasValue(baseLists.domains, tg.host) then return "work" end
    return nil
  end

  if tg.bid and tg.bid ~= "" then
    if baseLists.blockAppIDs[tg.bid] then return "block" end
    if baseLists.workAppIDs[tg.bid] then return "work" end
  end

  if tg.name and tg.name ~= "" then
    if hasValue(baseLists.blockApps, tg.name) then return "block" end
    if hasValue(baseLists.workApps, tg.name) then return "work" end
  end

  return nil
end

local function snapshotBase()
  for _, k in ipairs({"workApps", "blockApps", "domains", "blockDomains"}) do
    baseLists[k] = {}
    for _, v in ipairs(cfg[k]) do table.insert(baseLists[k], v) end
  end
  for _, k in ipairs({"workAppIDs", "blockAppIDs"}) do
    baseLists[k] = {}
    for kk, vv in pairs(cfg[k]) do baseLists[k][kk] = vv end
  end
end

local function restoreBase()
  for _, k in ipairs({"workApps", "blockApps", "domains", "blockDomains"}) do
    local copy = {}
    for _, v in ipairs(baseLists[k]) do table.insert(copy, v) end
    cfg[k] = copy
  end
  for _, k in ipairs({"workAppIDs", "blockAppIDs"}) do
    local copy = {}
    for kk, vv in pairs(baseLists[k]) do copy[kk] = vv end
    cfg[k] = copy
  end
end

-- 先还原基础名单, 再叠加覆盖(幂等), 增删都走这里 → 不用 reload, 计时不会被打断
local function applyOverrides()
  restoreBase()

  for _, tg in ipairs(overrides.targets) do
    local work = (tg.kind == "work")

    if tg.host and tg.host ~= "" then
      local list = work and cfg.domains or cfg.blockDomains
      if not hasValue(list, tg.host) then table.insert(list, tg.host) end
    else
      local ids = work and cfg.workAppIDs or cfg.blockAppIDs
      if tg.bid and tg.bid ~= "" then ids[tg.bid] = true end

      local names = work and cfg.workApps or cfg.blockApps
      if tg.name and tg.name ~= "" and not hasValue(names, tg.name) then
        table.insert(names, tg.name)
      end
    end
  end

  -- 覆盖必须能压过 init.lua 的基础名单: 把同一目标从对侧名单里移除
  -- (否则"把 Infuse 归到白名单"会无效 —— 基础黑名单里仍然有它)
  for _, tg in ipairs(overrides.targets) do
    local work = (tg.kind == "work")

    if tg.host and tg.host ~= "" then
      removeValue(work and cfg.blockDomains or cfg.domains, tg.host)
    else
      if tg.bid and tg.bid ~= "" then
        local ids = work and cfg.blockAppIDs or cfg.workAppIDs
        ids[tg.bid] = nil
      end

      if tg.name and tg.name ~= "" then
        removeValue(work and cfg.blockApps or cfg.workApps, tg.name)
      end
    end
  end
end

-- 归类/改方向(同一个目标再归一次 = 换边)
local function addTarget(kind, t)
  local host = t.host and t.host:lower():gsub("^www%.", ""):gsub("%.$", "") or ""
  local tg = {kind = kind, type = (host ~= "") and "host" or "app",
              name = t.name or "", bid = t.bid or "", host = host, at = os.time()}
  local key = targetKeyOf(tg)

  local baseSide = baseSideOf(tg)

  -- 基础名单里本来就是这一侧 → 不用存覆盖(避免"归了个寂寞"还多出一条记录)
  if baseSide == kind then
    return "already"
  end

  local status = (baseSide ~= nil) and "overrode" or "added"

  for _, old in ipairs(overrides.targets) do
    if targetKeyOf(old) == key then
      old.kind = kind
      if tg.name ~= "" then old.name = tg.name end
      if tg.bid  ~= "" then old.bid  = tg.bid  end
      saveOverrides()
      applyOverrides()
      return status
    end
  end

  table.insert(overrides.targets, tg)
  saveOverrides()
  applyOverrides()
  return status
end

local function removeTargetAt(index)
  local tg = overrides.targets[index]
  if not tg then return nil end

  local label = targetLabelOf(tg)
  local baseSide = baseSideOf(tg)

  table.remove(overrides.targets, index)
  saveOverrides()
  applyOverrides()

  return label, baseSide
end

local function clearTargets()
  overrides.targets = {}
  saveOverrides()
  applyOverrides()
end

snapshotBase()
applyOverrides()

-- ==========================================
-- 1c. 历史归类永久化
--   当天归类留在 focus-list-overrides.json(可逐条撤销);
--   隔天的自动"永久化" —— 默认写进 focus-lists-merged.json(不动源码, 适合 git 安装),
--   也可以设 cfg.mergeAgedIntoSource = true 让它直接改 init.lua 里的名单。
-- ==========================================

local initPath   = hs.configdir .. "/init.lua"
local mergedPath = hs.configdir .. "/focus-lists-merged.json"

-- 已永久化的条目(和 init.lua 里的名单等价, 只是单独存一份)
local mergedTargets = {}

do
  local f = io.open(mergedPath, "r")
  if f then
    f:close()
    local data = hs.json.read(mergedPath) or {}
    if type(data) == "table" and type(data.targets) == "table" then
      for _, v in ipairs(data.targets) do table.insert(mergedTargets, v) end
    end
  end
end

local function saveMerged()
  if not hs.json.write({targets = mergedTargets}, mergedPath, true, true) then
    print("Focus Timer: 永久归类保存失败")
  end
end

local function isSameDay(t)
  if type(t) ~= "number" or t <= 0 then return false end
  return os.date("%Y-%m-%d", t) == os.date("%Y-%m-%d")
end

local function agedCount()
  local n = 0
  for _, tg in ipairs(overrides.targets) do
    if not isSameDay(tg.at) then n = n + 1 end
  end
  return n
end

-- 把一个目标写进 baseLists 的对应侧(对侧同时移掉, 保证不矛盾)
local function applyOneToBase(tg)
  local wantWork = (tg.kind == "work")

  if tg.host and tg.host ~= "" then
    local list = wantWork and baseLists.domains or baseLists.blockDomains
    local opp  = wantWork and baseLists.blockDomains or baseLists.domains
    if not hasValue(list, tg.host) then table.insert(list, tg.host) end
    removeValue(opp, tg.host)
    return
  end

  if tg.bid and tg.bid ~= "" then
    if wantWork then
      baseLists.workAppIDs[tg.bid] = true
      baseLists.blockAppIDs[tg.bid] = nil
    else
      baseLists.blockAppIDs[tg.bid] = true
      baseLists.workAppIDs[tg.bid] = nil
    end
  end

  if tg.name and tg.name ~= "" then
    local list = wantWork and baseLists.workApps or baseLists.blockApps
    local opp  = wantWork and baseLists.blockApps or baseLists.workApps
    if not hasValue(list, tg.name) then table.insert(list, tg.name) end
    removeValue(opp, tg.name)
  end
end

local function applyMergedToBase()
  for _, tg in ipairs(mergedTargets) do applyOneToBase(tg) end
end

-- ---------- 可选: 直接改写 init.lua 名单(mergeAgedIntoSource = true) ----------

local function tableSpan(text, name)
  local s = text:find("\n  " .. name .. " = {", 1, true)
  if not s then return nil end
  local e = text:find("\n  }", s, true)
  if not e then return nil end
  return s, e
end

local function insertIntoTable(text, name, literal, rowText)
  local s, e = tableSpan(text, name)
  if not s or not e then return text, false end

  if text:sub(s, e - 1):find(literal, 1, true) then return text, false end

  local prefix = text:sub(1, e - 1)

  -- 在最后一行补逗号; 别补进行尾注释里(否则逗号被注释掉, 表就断了)
  local body, lastLine = prefix:match("^(.*\n)([^\n]*)$")
  if not body then body, lastLine = "", prefix end

  local code, comment = lastLine:match("^(.-)(%-%-.*)$")
  if not code then code, comment = lastLine, "" end

  if code:find("%S") then
    local c = code:gsub("%s+$", "")
    local last = c:sub(-1)
    if last ~= "," and last ~= "{" and last ~= "(" then c = c .. "," end
    lastLine = c .. ((comment ~= "") and ("  " .. comment) or "")
  end

  return body .. lastLine .. "\n    " .. rowText .. "\n" .. text:sub(e), true
end

local function removeFromTable(text, name, literal)
  local s, e = tableSpan(text, name)
  if not s or not e then return text, false end

  local span = text:sub(s, e - 1)
  if not span:find(literal, 1, true) then return text, false end

  local kept = {}
  for line in (span .. "\n"):gmatch("([^\n]*)\n") do
    if not line:find(literal, 1, true) then table.insert(kept, line) end
  end

  return text:sub(1, s - 1) .. table.concat(kept, "\n") .. text:sub(e), true
end

-- 把隔天的归类永久化。返回: 处理条数, 跳过条数
local function mergeAgedTargets()
  if #overrides.targets == 0 then return 0, 0 end

  local aged, kept = {}, {}
  for _, tg in ipairs(overrides.targets) do
    if isSameDay(tg.at) then table.insert(kept, tg) else table.insert(aged, tg) end
  end

  if #aged == 0 then return 0, 0 end

  -- ---- 默认: 写进 focus-lists-merged.json, 不改源码 ----
  if not cfg.mergeAgedIntoSource then
    for _, tg in ipairs(aged) do
      local key, dup = targetKeyOf(tg), false
      for _, m in ipairs(mergedTargets) do
        if targetKeyOf(m) == key then dup = true; m.kind = tg.kind; break end
      end
      if not dup then table.insert(mergedTargets, tg) end
    end

    saveMerged()

    overrides.targets = kept
    saveOverrides()

    applyMergedToBase()
    applyOverrides()

    print(string.format("Focus Timer: %d 条历史归类已永久化(focus-lists-merged.json)", #aged))
    return #aged, 0
  end

  -- ---- 可选: 直接改写 init.lua ----
  local f = io.open(initPath, "r")
  if not f then return 0, 0 end
  local text = f:read("*a")
  f:close()

  local inserted, skipped = 0, 0

  for _, tg in ipairs(aged) do
    local wantWork = (tg.kind == "work")

    if baseSideOf(tg) == tg.kind then
      skipped = skipped + 1
    else
      local touched = false

      if tg.host and tg.host ~= "" then
        local lit      = '"' .. tg.host .. '"'
        local addName  = wantWork and "domains" or "blockDomains"
        local dropName = wantWork and "blockDomains" or "domains"
        local ok

        text = removeFromTable(text, dropName, lit)
        text, ok = insertIntoTable(text, addName, lit, lit .. ",")
        touched = ok
      else
        local idLit, nameLit
        if tg.bid and tg.bid ~= "" then idLit = '["' .. tg.bid .. '"]' end
        if tg.name and tg.name ~= "" then nameLit = '"' .. tg.name .. '"' end

        local addIds, dropIds, addNames, dropNames
        if wantWork then
          addIds, dropIds = "workAppIDs", "blockAppIDs"
          addNames, dropNames = "workApps", "blockApps"
        else
          addIds, dropIds = "blockAppIDs", "workAppIDs"
          addNames, dropNames = "blockApps", "workApps"
        end

        if idLit then text = removeFromTable(text, dropIds, idLit) end
        if nameLit then text = removeFromTable(text, dropNames, nameLit) end

        local ok
        if idLit then
          text, ok = insertIntoTable(text, addIds, idLit, idLit .. " = true,")
          touched = touched or ok
        end
        if nameLit then
          text, ok = insertIntoTable(text, addNames, nameLit, nameLit .. ",")
          touched = touched or ok
        end
      end

      if touched then inserted = inserted + 1 else skipped = skipped + 1 end
    end
  end

  if inserted > 0 then
    -- 语法自检: 不通过就绝不写盘
    local loader = loadstring or load
    local chunk, err = loader(text, "init.lua")
    if not chunk then
      print("Focus Timer: 合并后语法自检失败, 已放弃: " .. tostring(err))
      return -1, 0
    end

    local bak = initPath .. ".bak-" .. os.date("%Y%m%d-%H%M%S")
    local rf = io.open(initPath, "r")
    local old = rf:read("*a")
    rf:close()

    local bf = io.open(bak, "w")
    bf:write(old)
    bf:close()

    -- 备份只留最近 5 份
    local list = {}
    local p = io.popen("ls -1t " .. initPath .. ".bak-* 2>/dev/null")
    if p then
      for line in p:lines() do table.insert(list, line) end
      p:close()
    end
    for i = 6, #list do os.remove(list[i]) end

    local wf = io.open(initPath, "w")
    wf:write(text)
    wf:close()

    -- 运行时同步, 不 reload(避免把当前倒计时清零)
    for _, tg in ipairs(aged) do
      if baseSideOf(tg) ~= tg.kind then applyOneToBase(tg) end
    end
    applyOverrides()
    print(string.format("Focus Timer: 已把 %d 条历史归类写进 init.lua(备份 .bak-*)", inserted))
  end

  overrides.targets = kept
  saveOverrides()

  return inserted, skipped
end

-- 加载时先永久化一次
mergeAgedTargets()

applyMergedToBase()
applyOverrides()


local function saveSettings()
  local data = {
    unknownPolicy            = cfg.unknownPolicy,
    workMinutes              = math.floor(cfg.workSeconds / 60 + 0.5),
    breakMinutes             = math.floor(cfg.breakSeconds / 60 + 0.5),
    longBreakMinutes         = math.floor(cfg.longBreakSeconds / 60 + 0.5),
    pomodorosBeforeLongBreak = cfg.pomodorosBeforeLongBreak
  }

  if not hs.json.write(data, settingsPath, true, true) then
    print("Focus Timer: 设置保存失败")
  end
end

local statsPath = hs.configdir .. "/focus-stats.json"
local saved = hs.json.read(statsPath) or {}
local stats = saved.days or {}

local phase = "work"
local remaining = cfg.workSeconds
local locked = false
local focusEnabled = false
local pendingAutoWork = false
local lastTick = hs.timer.secondsSinceEpoch()
local lastSave = lastTick
local currentDay = os.date("%Y-%m-%d")
local lastKind = "unknown"
local currentLabel = "-"
local lastEffectiveKind = nil   -- 已经生效的分类(切换要等 settleSeconds 才更新)
local pendingKind, pendingSince = nil, 0

-- ⚠️ hs.timer / hs.caffeinate.watcher / hs.menubar 返回的对象必须保留强引用,
-- 否则被 Lua GC 回收后**静默停止**(2026-10-27 实测: 定时器 5 秒后停摆, 无任何报错)。
-- 这里统一挂到全局表上, 保证配置 chunk 返回后这些对象仍被引用。
local runtime = {}
_G.FocusTimerRuntime = runtime

local menu = runtime.menu or hs.menubar.new()
runtime.menu = menu

local function blankDay()
  return {
    work = 0,
    rest = 0,
    paused = 0,
    pomodoros = 0
  }
end

local function getDay(key)
  key = key or os.date("%Y-%m-%d")
  if not stats[key] then
    stats[key] = blankDay()
  end
  return stats[key]
end

local function saveStats()
  local ok = hs.json.write({
    version = 1,
    days = stats
  }, statsPath, true, true)

  if not ok then
    print("Focus Timer: 统计保存失败")
  end

  lastSave = hs.timer.secondsSinceEpoch()
end

local function formatTime(seconds)
  seconds = math.floor((seconds or 0) + 0.5)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)

  return string.format("%d小时%02d分", h, m)
end

-- ==========================================
-- 2. 声音
-- ==========================================

-- 带扩展名的从本地 sounds 目录读(兼容 mp3/wav), 否则当系统提示音
local function resolveSound(name)
  if not name then return nil end

  if name:match("%.%w+$") then
    local path = hs.configdir .. "/" .. (cfg.soundDir or "sounds") .. "/" .. name
    return hs.sound.getByFile(path)
  end

  return hs.sound.getByName(name)
end

local function playSound(event)
  local name = cfg.sounds[event]
  if not name then return end

  local times = (cfg.soundRepeat and cfg.soundRepeat[event]) or 1
  local gap = cfg.soundGap or 0.6
  local vol = cfg.soundVolume

  if event == "tick" and cfg.tickVolume then vol = cfg.tickVolume end

  local function playOnce()
    local s = resolveSound(name)
    if not s then return end
    if vol then s:volume(vol) end
    s:play()
    runtime.playCount = (runtime.playCount or 0) + 1
    runtime.lastPlayed = name
  end

  playOnce()

  for i = 1, times - 1 do
    -- ⚠️ 连响用的定时器必须留强引用, 否则被 GC 掉就只响第一声
    runtime.soundTimers = runtime.soundTimers or {}
    runtime.soundTimers[#runtime.soundTimers + 1] = hs.timer.doAfter(i * gap, playOnce)

    -- 别无限攒
    while #runtime.soundTimers > 20 do table.remove(runtime.soundTimers, 1) end
  end
end

-- ==========================================
-- 3. macOS 专注模式
-- ==========================================

local function runShortcut(name)
  local task = hs.task.new(
    "/usr/bin/shortcuts",
    function(code, output, errorOutput)
      if code ~= 0 then
        print("Shortcut failed: " .. name)
        print(errorOutput or output or "")
      end
    end,
    {"run", name}
  )

  if task then task:start() end
end

local function setFocus(enabled)
  if not cfg.focusModeEnabled then return end   -- 没配快捷指令就跳过
  if focusEnabled == enabled then return end
  focusEnabled = enabled

  runShortcut(
    enabled and cfg.focusOnShortcut
            or cfg.focusOffShortcut
  )
end

-- ==========================================
-- 4. App / 网站识别
-- ==========================================

local function browserURL(name)
  local script

  if name == "Safari" then
    script = [[
      tell application "Safari"
        return URL of front document
      end tell
    ]]
  elseif cfg.chromiumBrowsers[name] then
    script = string.format([[
      tell application "%s"
        return URL of active tab of front window
      end tell
    ]], name)
  else
    return nil
  end

  local ok, result = hs.osascript.applescript(script)

  if ok and type(result) == "string" then
    return result
  end

  return nil
end

local function matchIDs(ids, names, name, bid)
  if bid and bid ~= "" and ids[bid] then return true end

  if name and name ~= "" then
    local lname = name:lower()
    for _, n in ipairs(names) do
      if n:lower() == lname then return true end
    end
  end

  return false
end

-- 域名命中长度（最长匹配优先，越具体越优先）
local function domainScore(host, list)
  local best = 0

  for _, domain in ipairs(list) do
    domain = domain:lower()

    if host == domain or host:sub(-#domain - 1) == "." .. domain then
      if #domain > best then best = #domain end
    end
  end

  return best
end

-- App 名单判定（非浏览器）
local function appKind(name, bid)
  if matchIDs(cfg.blockAppIDs, cfg.blockApps, name, bid) then
    return "block", (name or "?") .. "（黑名单 App）"
  end
  if matchIDs(cfg.workAppIDs, cfg.workApps, name, bid) then
    return "work", name or "?"
  end
  return "unknown", name or "?"
end

-- 网站名单判定（黑名单优先，取最长匹配；同长度时黑名单胜）
local function hostKind(name, host)
  host = host:lower():gsub("%.$", "")
  local label = (name or "浏览器") .. ": " .. host

  local blockScore = domainScore(host, cfg.blockDomains)
  local workScore = domainScore(host, cfg.domains)

  if blockScore > 0 and blockScore >= workScore then
    return "block", label .. "（黑名单网站）"
  end
  if workScore > 0 then
    return "work", label
  end
  return "unknown", label
end

-- 返回 "work" / "block" / "unknown" 和可读标签
-- 显式传 host = 只判网站；显式传 name = 判该应用；都不传 = 读当前前台应用
local function classify(name, bid, host)
  if host then
    return hostKind(name, host)
  end

  if name then
    if name == "Safari" or cfg.chromiumBrowsers[name] then
      local url = browserURL(name)
      local h = url and url:match("^https?://([^/:?#]+)") or nil

      if h then return hostKind(name, h) end
      return "unknown", name .. "（读不到网址）"
    end

    return appKind(name, bid)
  end

  local app = hs.application.frontmostApplication()
  if not app then return "unknown", "无前台应用" end

  local fname = app:name()
  if not fname then return "unknown", "前台应用无名" end

  return classify(fname, app:bundleID(), nil)
end

-- 纯函数版判定（便于自测：不碰前台应用）
local function kindOfApp(name, bid)
  return classify(name, bid, nil)
end

local function kindOfHost(host)
  return classify("浏览器", "", host)
end

-- kind = 本轮识别结果
-- ⚠️ 未知目标"保持"的必须是**最近一次明确判定**的状态(work/block 的结果),
-- 不能拿上一轮 tick 的分类结果当依据 —— 否则切到未知应用后第一秒是"保持",
-- 从第二秒起 prev 已经变成 unknown, 立刻退回暂停(2026-10-27 实测踩坑)。
local lastKnownDecision = nil

local function decide(kind)
  if locked then return false end
  if hs.host.idleTime() >= cfg.idleSeconds then return false end

  if kind == "work" then
    lastKnownDecision = true
    return true
  end

  if kind == "block" then
    lastKnownDecision = false
    return false
  end

  if cfg.unknownPolicy == "keep" then
    return lastKnownDecision == true
  end

  return false
end

-- ==========================================
-- 4b. 手动归类面板（白名单 / 黑名单）
-- ==========================================

local function currentTarget()
  local app = hs.application.frontmostApplication()
  if not app then return nil end

  local name = app:name()
  if not name then return nil end

  local t = { name = name, bid = app:bundleID() or "" }

  if name == "Safari" or cfg.chromiumBrowsers[name] then
    local url = browserURL(name)
    t.host = url and url:match("^https?://([^/:?#]+)") or nil
  end

  return t
end

local function targetKey(t)
  if t.host then return "host:" .. t.host:lower() end
  return "app:" .. ((t.bid ~= "") and t.bid or t.name)
end

local function targetLabel(t)
  if t.host then return t.name .. ": " .. t.host end
  return t.name
end

-- 归类面板(键盘可选, 也可鼠标点)
local function offerClassify(t)
  local label = targetLabel(t)

  if runtime.chooser then
    runtime.chooser:hide()
    runtime.chooser = nil
  end

  local chooser = hs.chooser.new(function(choice)
    runtime.chooser = nil
    if runtime.panelTimer then runtime.panelTimer:stop(); runtime.panelTimer = nil end
    if not choice then return end          -- 取消: 什么都不记

    local status = addTarget(choice.action, t)
    local side = (choice.action == "work") and "白名单" or "黑名单"
    local msg

    if status == "already" then
      msg = "ℹ️ " .. label .. "\n本来就在 init.lua 的" .. side .. "里，无需归类"
    elseif status == "overrode" then
      msg = (choice.action == "work" and "💻 已加入白名单: " or "🎮 已加入黑名单: ") .. label ..
            "\n（已覆盖 init.lua 里的" .. ((choice.action == "work") and "黑名单" or "白名单") .. "归类）"
    else
      msg = (choice.action == "work" and "💻 已加入白名单: " or "🎮 已加入黑名单: ") .. label
    end

    hs.alert.show(msg, 4)

    -- 手动归类后立刻按新分类走, 不要再等 settleSeconds
    lastEffectiveKind = nil
    pendingKind, pendingSince = nil, 0
  end)

  chooser:placeholderText("归类: " .. label)
  chooser:choices({
    {text = "💻 加入白名单(算工作)",   subText = label, action = "work"},
    {text = "🎮 加入黑名单(暂停计时)", subText = label, action = "block"}
  })

  runtime.chooser = chooser    -- 必须强引用, 否则被 GC 掉弹不出来
  chooser:show()

  -- 没人理就自动收起(只是收起, 什么都不会记)
  if runtime.panelTimer then runtime.panelTimer:stop() end
  runtime.panelTimer = hs.timer.doAfter(cfg.panelTimeout or 30, function()
    if runtime.chooser then
      runtime.chooser:hide()
      runtime.chooser = nil
    end
    runtime.panelTimer = nil
  end)
end


-- ==========================================
-- 5. 计时与统计
-- ==========================================

-- 做完第 count 个番茄后该不该长休息
local function isLongBreakAfter(count)
  local n = cfg.pomodorosBeforeLongBreak
  return n > 0 and count % n == 0
end

-- isLong = true 时进长休息(每 N 个番茄一次)
local function enterBreak(isLong)
  phase = "break"
  remaining = isLong and cfg.longBreakSeconds or cfg.breakSeconds
  pendingAutoWork = false
  lastKind = "unknown"
  lastKnownDecision = nil
  lastEffectiveKind = nil
  pendingKind, pendingSince = nil, 0

  setFocus(false)
  playSound(isLong and "longRest" or "rest")

  if isLong then
    hs.alert.show(string.format("🛋 长休息 %d 分钟（已完成 %d 个番茄）  想做完了再休息？菜单 ⏰ 撤回休息",
      math.floor(cfg.longBreakSeconds / 60 + 0.5),
      getDay().pomodoros))
  else
    hs.alert.show("☕ 该休息了  想做完了再休息？菜单 ⏰ 撤回休息", 5)
  end

  saveStats()
end

local function enterWork(manual)
  phase = "work"
  remaining = cfg.workSeconds
  pendingAutoWork = not manual
  lastKind = "unknown"
  lastKnownDecision = nil
  lastEffectiveKind = nil
  pendingKind, pendingSince = nil, 0

  if manual then
    playSound("manualWork")
    hs.alert.show("💻 手动开始工作")
  else
    hs.alert.show("💻 休息结束，准备工作")
  end

  saveStats()
end

local function updateMenu(running)
  local seconds = math.max(0, math.ceil(remaining))
  local mins = math.floor(seconds / 60)
  local secs = seconds % 60

  local prefix = phase == "work" and "💻" or "☕"
  local pause = running and "" or "⏸"
  -- ❓ = 当前前台目标不在任何名单里(需要时自己去归类)。
  -- 注意: 这只是个静态标识, 不做通知/弹窗/提醒。
  local mark = (phase == "work" and lastKind == "unknown") and "❓" or ""

  menu:setTitle(string.format(
    "%s%s%s %02d:%02d",
    prefix, pause, mark, mins, secs
  ))
end

-- 延长工作: 工作阶段 → 直接加时间; 休息阶段 → 撤回休息, 继续做 N 分钟
local function extendWork(minutes)
  minutes = tonumber(minutes) or 5

  if phase == "work" then
    remaining = remaining + minutes * 60
    hs.alert.show(string.format("⏰ 已延长 %d 分钟（本轮还剩 %d 分 %02d 秒）",
      minutes, math.floor(remaining / 60), math.floor(remaining % 60)), 4)
  else
    phase = "work"
    remaining = minutes * 60
    pendingAutoWork = false
    lastKind = "unknown"
    lastKnownDecision = nil
    hs.alert.show(string.format("⏰ 已撤回休息，继续工作 %d 分钟", minutes), 4)
  end

  lastTick = hs.timer.secondsSinceEpoch()
  updateMenu(phase == "work")
  saveStats()
end


local function tick()
  local now = hs.timer.secondsSinceEpoch()
  local delta = math.max(0, math.min(now - lastTick, 2))
  lastTick = now

  local today = os.date("%Y-%m-%d")

  if today ~= currentDay then
    saveStats()
    currentDay = today
    mergeAgedTargets()      -- 跨天: 把昨天的归类沉淀进 init.lua
  end

  local day = getDay(today)
  local running = false

  if phase == "work" then
    local kind, label = classify()
    lastKind = kind
    currentLabel = label

    -- 切到别的应用不立刻暂停/开始: 新分类要连续稳定 cfg.settleSeconds 秒才算数
    local settle = cfg.settleSeconds or 0
    local effective

    if settle <= 0 or lastEffectiveKind == nil or kind == lastEffectiveKind then
      lastEffectiveKind = kind
      pendingKind, pendingSince = nil, 0
      effective = kind
    elseif pendingKind ~= kind then
      pendingKind, pendingSince = kind, now
      effective = lastEffectiveKind           -- 还在观察期, 先沿用原状态
    elseif now - pendingSince >= settle then
      lastEffectiveKind = kind               -- 稳定够了, 正式切换
      pendingKind, pendingSince = nil, 0
      effective = kind
    else
      effective = lastEffectiveKind
    end

    running = decide(effective)

    setFocus(running)

    if running and pendingAutoWork then
      pendingAutoWork = false
      playSound("autoWork")
      hs.alert.show("💻 进入工作状态")
    end

    if running then
      day.work = day.work + delta
    elseif not locked then
      -- 锁屏/睡眠时间不计入暂停统计
      day.paused = day.paused + delta
    end

  elseif phase == "break" then
    -- 休息期间允许切换应用或不操作
    -- 锁屏时暂停休息倒计时
    running = not locked

    setFocus(false)

    if running then
      day.rest = day.rest + delta

      -- 休息中每秒滴答一声(Pomotroid 的 tick 音)
      if cfg.breakTick then playSound("tick") end
    end
  end

  if running then
    remaining = remaining - delta

    if remaining <= 0 then
      if phase == "work" then
        day.pomodoros = day.pomodoros + 1
        -- 每完成 N 个番茄 → 长休息
        enterBreak(isLongBreakAfter(day.pomodoros))
      else
        enterWork(false)
      end

      running = false
    end
  end

  updateMenu(running)

  if now - lastSave >= cfg.saveInterval then
    saveStats()
  end
end

-- ==========================================
-- 6. 锁屏、解锁、睡眠
-- ==========================================

local events = hs.caffeinate.watcher

local lockWatcher = events.new(function(event)
  if event == events.screensDidLock or
     event == events.systemWillSleep or
     event == events.sessionDidResignActive then

    locked = true
    setFocus(false)
    lastTick = hs.timer.secondsSinceEpoch()
    updateMenu(false)
    saveStats()

  elseif event == events.screensDidUnlock or
         event == events.sessionDidBecomeActive or
         event == events.systemDidWake then

    -- 唤醒后不补算睡眠/锁屏时长
    locked = false
    lastKind = "unknown"
    lastTick = hs.timer.secondsSinceEpoch()
    tick()
  end
end)

runtime.lockWatcher = lockWatcher
lockWatcher:start()

-- ==========================================
-- 7. 统计菜单
-- ==========================================

local function todayStatsMenu()
  local day = getDay()
  return {
    {
      title = "有效工作：" .. formatTime(day.work),
      disabled = true
    },
    {
      title = "正式休息：" .. formatTime(day.rest),
      disabled = true
    },
    {
      title = "暂停时间：" .. formatTime(day.paused),
      disabled = true
    },
    {
      title = "完成番茄钟：" .. day.pomodoros .. " 个",
      disabled = true
    },
    {
      title = string.format("再 %d 个进长休息（每 %d 个一次）",
        cfg.pomodorosBeforeLongBreak - (day.pomodoros % cfg.pomodorosBeforeLongBreak),
        cfg.pomodorosBeforeLongBreak),
      disabled = true
    }
  }
end

local function weekStatsMenu()
  local items = {}
  local sum = blankDay()

  -- 用当天中午生成日期，避免夏令时造成日期偏移
  local now = os.date("*t")
  now.hour = 12
  now.min = 0
  now.sec = 0
  local noon = os.time(now)

  for i = 0, 6 do
    local key = os.date("%Y-%m-%d", noon - i * 86400)
    local day = stats[key] or blankDay()

    sum.work = sum.work + day.work
    sum.rest = sum.rest + day.rest
    sum.paused = sum.paused + day.paused
    sum.pomodoros = sum.pomodoros + day.pomodoros

    table.insert(items, {
      title = string.format(
        "%s  工作 %s / 休息 %s",
        key,
        formatTime(day.work),
        formatTime(day.rest)
      ),
      disabled = true
    })
  end

  table.insert(items, {title = "-"})

  table.insert(items, {
    title = "7天工作合计：" .. formatTime(sum.work),
    disabled = true
  })
  table.insert(items, {
    title = "7天休息合计：" .. formatTime(sum.rest),
    disabled = true
  })
  table.insert(items, {
    title = "7天暂停合计：" .. formatTime(sum.paused),
    disabled = true
  })
  table.insert(items, {
    title = "完成番茄钟：" .. sum.pomodoros .. " 个",
    disabled = true
  })

  return items
end

-- 菜单栏里看名单规模（自服务：不用去翻配置）
local function rosterMenu()
  local function countSet(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
  end

  return {
    {
      title = string.format("白名单 App：%d 个（bundle id %d 条）",
        #cfg.workApps, countSet(cfg.workAppIDs)),
      disabled = true
    },
    {
      title = string.format("黑名单 App：%d 个（bundle id %d 条）",
        #cfg.blockApps, countSet(cfg.blockAppIDs)),
      disabled = true
    },
    {
      title = string.format("白名单网站：%d 个", #cfg.domains),
      disabled = true
    },
    {
      title = string.format("黑名单网站：%d 个", #cfg.blockDomains),
      disabled = true
    },
    {
      title = string.format("我归的类：%d 个目标", overriddenCount()),
      disabled = true
    }
  }
end

-- 逐条撤销：我归的类
local function overrideMenu()
  if #overrides.targets == 0 then
    return {{title = "（还没有归过任何目标）", disabled = true}}
  end

  local items = {}

  for i, tg in ipairs(overrides.targets) do
    items[i] = {
      title = string.format("%s %s%s   ← 点击撤销",
        (tg.kind == "work") and "💻" or "🎮", targetLabelOf(tg),
        baseSideOf(tg) and "（init.lua 里另有归类）" or ""),
      fn = function()
        local label, baseSide = removeTargetAt(i)
        local msg = "↩️ 已撤销我归的类: " .. tostring(label)

        if baseSide == "block" then
          msg = msg .. "\ninit.lua 基础名单里它仍是黑名单 → 继续按暂停处理"
        elseif baseSide == "work" then
          msg = msg .. "\ninit.lua 基础名单里它仍是白名单 → 继续按工作处理"
        else
          msg = msg .. "\n现在按未归类处理(既不算工作也不暂停)"
        end

        hs.alert.show(msg, 5)
      end
    }
  end

  table.insert(items, {title = "-"})
  table.insert(items, {
    title = "🧹 全部撤销（" .. #overrides.targets .. " 个目标）",
    fn = function()
      clearTargets()
      hs.alert.show("🧹 已全部撤销")
    end
  })

  return items
end

-- 番茄节奏设置：时长都能在菜单里改，存 focus-settings.json（下一轮生效，不动当前倒计时）
local function paceMenu()
  local function opt(cur, v, setter)
    return {title = (cur == v and "☑ " or "☐ ") .. tostring(v), fn = setter}
  end

  local function setWork(v)
    cfg.workSeconds = v * 60
    saveSettings()
    hs.alert.show(string.format("工作时间 = %d 分钟（下一轮生效）", v))
  end

  local function setBreak(v)
    cfg.breakSeconds = v * 60
    saveSettings()
    hs.alert.show(string.format("休息时间 = %d 分钟（下一次休息生效）", v))
  end

  local function setLong(v)
    cfg.longBreakSeconds = v * 60
    saveSettings()
    hs.alert.show(string.format("长休息 = %d 分钟", v))
  end

  local function setNum(v)
    cfg.pomodorosBeforeLongBreak = v
    saveSettings()
    hs.alert.show(string.format("每 %d 个番茄长休息一次", v))
  end

  local work  = math.floor(cfg.workSeconds / 60 + 0.5)
  local brk   = math.floor(cfg.breakSeconds / 60 + 0.5)
  local lng   = math.floor(cfg.longBreakSeconds / 60 + 0.5)
  local count = cfg.pomodorosBeforeLongBreak

  return {
    {
      title = string.format("工作 %d 分钟", work),
      menu = {
        opt(work, 25, function() setWork(25) end),
        opt(work, 30, function() setWork(30) end),
        opt(work, 45, function() setWork(45) end),
        opt(work, 50, function() setWork(50) end)
      }
    },
    {
      title = string.format("休息 %d 分钟", brk),
      menu = {
        opt(brk, 5,  function() setBreak(5) end),
        opt(brk, 10, function() setBreak(10) end),
        opt(brk, 15, function() setBreak(15) end)
      }
    },
    {
      title = string.format("长休息 %d 分钟", lng),
      menu = {
        opt(lng, 15, function() setLong(15) end),
        opt(lng, 20, function() setLong(20) end),
        opt(lng, 30, function() setLong(30) end),
        opt(lng, 45, function() setLong(45) end)
      }
    },
    {
      title = string.format("每 %d 个番茄长休息", count),
      menu = {
        opt(count, 3, function() setNum(3) end),
        opt(count, 4, function() setNum(4) end),
        opt(count, 5, function() setNum(5) end),
        opt(count, 6, function() setNum(6) end)
      }
    }
  }
end

-- 每次点击菜单栏时重新生成统计数据
menu:setMenu(function()
  local items = {
    {
      title = "🔍 当前识别：" .. currentLabel,
      disabled = true
    },
    {
      title = "🏷 归类当前前台目标…",
      fn = function()
        local t = currentTarget()
        if not t then
          hs.alert.show("没有前台应用")
          return
        end
        offerClassify(t)
      end
    },
    {
      title = "📋 名单一览",
      menu = rosterMenu()
    },

    {title = "-"},

    {
      title = "📊 今日统计",
      menu = todayStatsMenu()
    },
    {
      title = "📅 最近 7 天统计",
      menu = weekStatsMenu()
    },

    {title = "-"},

    {
      title = "⏱ 番茄节奏",
      menu = paceMenu()
    },

    {title = "-"},

    {
      title = "☕ 立即休息",
      fn = function()
        enterBreak(false)
        lastTick = hs.timer.secondsSinceEpoch()
        updateMenu(not locked)
      end
    },
    {
      title = "🛋 立即长休息",
      fn = function()
        enterBreak(true)
        lastTick = hs.timer.secondsSinceEpoch()
        updateMenu(not locked)
      end
    },
    {
      title = (phase == "break") and "⏰ 撤回休息，继续工作" or "⏰ 延长工作时间",
      menu = (function()
        local items = {}
        for _, m in ipairs(cfg.extensionMinutes or {5, 10, 15}) do
          table.insert(items, {
            title = string.format((phase == "break") and "继续工作 %d 分钟" or "延长 %d 分钟", m),
            fn = function() extendWork(m) end
          })
        end
        return items
      end)()
    },
    {
      title = "💻 立即开始工作",
      fn = function()
        enterWork(true)
        lastTick = hs.timer.secondsSinceEpoch()
        tick()
      end
    },

    {title = "-"},

    {
      title = (cfg.unknownPolicy == "keep" and "☑" or "☐") ..
              " 未知应用保持计时（关=未知即暂停）",
      fn = function()
        cfg.unknownPolicy = (cfg.unknownPolicy == "keep") and "pause" or "keep"
        saveSettings()
        lastKind = "unknown"
        hs.alert.show("未知应用：" ..
          (cfg.unknownPolicy == "keep" and "保持计时（Pomotroid 语义）" or "暂停"))
      end
    },

    {
      title = "🧹 合并历史归类（" .. agedCount() .. " 条待合并）",
      disabled = (agedCount() == 0),
      fn = function()
        local merged, skipped = mergeAgedTargets()

        if merged == -1 then
          hs.alert.show("合并失败，详见 Hammerspoon Console", 4)
        elseif merged == 0 then
          hs.alert.show("没有隔天的归类需要合并", 3)
        else
          hs.alert.show(string.format("已合并 %d 条进 init.lua（跳过 %d 条已在基础名单）",
            merged, skipped or 0), 4)
        end
      end
    },
    {
      title = "🏷 我归的类（" .. overriddenCount() .. " 个目标）",
      menu = overrideMenu()
    },

    {title = "-"},

    {
      title = "🔔 试听提示音",
      menu = {
        {title = "休息→工作（alert-work.mp3）", fn = function() playSound("autoWork") end},
        {title = "开始短休息（alert-short-break.mp3）", fn = function() playSound("rest") end},
        {title = "开始长休息（alert-long-break.mp3）", fn = function() playSound("longRest") end}
      }
    },
    {
      title = "🔄 重置工作计时",
      fn = function()
        phase = "work"
        remaining = cfg.workSeconds
        pendingAutoWork = false
        lastKind = "unknown"
        lastTick = hs.timer.secondsSinceEpoch()

        setFocus(false)
        saveStats()
        updateMenu(false)
        hs.alert.show("🔄 工作计时已重置")
      end
    },

    {title = "-"},

    {
      title = "💾 保存统计数据",
      fn = function()
        saveStats()
        hs.alert.show("统计数据已保存")
      end
    },
    {
      title = "⚙️ 重新加载配置",
      fn = function()
        saveStats()
        hs.reload()
      end
    }
  }

  return items
end)

-- 自测钩子（hs -c 里可用，方便验证名单，不用真的切应用）
_G.FocusTimer = {
  cfg = cfg,
  classify = classify,
  kindOfApp = kindOfApp,
  kindOfHost = kindOfHost,
  decide = decide,
  offerClassify = offerClassify,
  addTarget = addTarget,
  currentTarget = currentTarget,
  overrides = function() return overrides end,
  overrideCount = overriddenCount,
  removeTargetAt = removeTargetAt,
  clearTargets = clearTargets,
  targets = function() return overrides.targets end,
  overrideMenu = overrideMenu,
  paceMenu = paceMenu,
  isLongBreakAfter = isLongBreakAfter,
  extendWork = extendWork,
  playSound = playSound,
  enterBreak = function(isLong) enterBreak(isLong and true or false); return phase end,
  enterWork = function(manual) enterWork(manual and true or false); return phase end,
  playCount = function() return runtime.playCount or 0, runtime.lastPlayed end,
  phaseNow = function() return phase end,
  remainingNow = function() return remaining end,
  mergeAgedTargets = mergeAgedTargets,
  agedCount = agedCount,
  path = function() return overridePath end,
  debug = function()
    return string.format(
      "phase=%s remaining=%.1f locked=%s idle=%ds lastKind=%s policy=%s label=%s | ticks=%s last=%s err=%s | 覆盖=%d",
      phase, remaining, tostring(locked), math.floor(hs.host.idleTime()),
      lastKind, cfg.unknownPolicy, currentLabel,
      tostring(runtime.ticks), tostring(runtime.lastTickAt), tostring(runtime.lastError),
      overriddenCount()) .. " | 沿用=" .. tostring(lastKnownDecision)
      .. string.format(" | 生效=%s 待定=%s%.0fs", tostring(lastEffectiveKind), tostring(pendingKind),
         pendingSince > 0 and (hs.timer.secondsSinceEpoch() - pendingSince) or 0)
  end,
  current = function()
    local kind, label = classify()
    return kind .. " | " .. label
  end
}

-- ==========================================
-- 8. 启动
-- ==========================================

getDay()

-- 单次 tick 异常不能让定时器死掉(回调抛错会让 hs.timer 停表), 用 xpcall 兜住并记日志
local function guardedTick()
  local ok, err = xpcall(tick, debug.traceback)
  runtime.ticks = (runtime.ticks or 0) + 1
  runtime.lastTickAt = os.date("%H:%M:%S")

  if not ok then
    runtime.lastError = tostring(err)
    print("Focus Timer tick 异常: " .. tostring(err))
  end
end

runtime.timer = hs.timer.doEvery(1, guardedTick)
tick()

hs.alert.show("Smart Focus Timer 已启动")
