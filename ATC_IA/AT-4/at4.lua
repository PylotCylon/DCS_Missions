-- =========================================================
-- E111 AT-4: TOT + AAR reserve + SEAD evaluator + SA-2 random activation
-- Works even if DCS sandbox disables os, math.randomseed, math.random.
-- Paste in: MISSION START -> DO SCRIPT
-- =========================================================

-- =========================
-- 0) COMMON HELPERS
-- =========================
local function _now() return timer.getTime() end

local function _msg(txt, secs)
  trigger.action.outText(txt, secs or 8)
end

local function _setFlag(flag, val)
  trigger.action.setUserFlag(flag, val)
end

local function _getZone(name)
  return trigger.misc.getZone(name)
end

local function _dist2D(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return math.sqrt(dx*dx + dz*dz)
end

local function _formatClock(sec)
  sec = math.floor(sec + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  return string.format("%02d:%02d:%02d", h, m, s)
end

local function _formatDelta(sec)
  sec = math.floor(sec + 0.5)
  local sign = (sec < 0) and "-" or "+"
  sec = math.abs(sec)
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format("%s%02d:%02d", sign, m, s)
end

-- =========================
-- 0.5) SIMPLE RNG (no math.randomseed/random needed)
-- with better seeding for DCS (editor restarts)
-- =========================
AT4_RNG = AT4_RNG or {}

local function _seedFromString(s)
  -- simple string hash -> 31-bit int
  local h = 0
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 2147483647
  end
  if h < 1 then h = 1234567 end
  return h
end

do
  local t1 = 0
  local t2 = 0
  if timer and timer.getAbsTime then t1 = timer.getAbsTime() end
  if timer and timer.getTime then t2 = timer.getTime() end

  -- This changes every mission run: table address string
  local addr = tostring({})

  local seedStr = string.format("%s|%0.3f|%0.3f", addr, t1, t2)
  AT4_RNG.seed = _seedFromString(seedStr)
end

function AT4_RNG.next()
  AT4_RNG.seed = (1103515245 * AT4_RNG.seed + 12345) % 2147483647
  return AT4_RNG.seed
end

function AT4_RNG.int(min, max)
  local r = AT4_RNG.next()
  return (r % (max - min + 1)) + min
end

function AT4_RNG.pct(p)
  return AT4_RNG.int(1, 100) <= p
end

-- =========================
-- 1) RANDOM SA-2 ACTIVATION (8 pre-placed groups, Late Activation)
-- DEBUG version: shows which group was picked
-- =========================
do
  local candidates = {
    "Ground-1_A",
    "Ground-1_B",
    "Ground-1_C",
    "Ground-1_D",
    "Ground-1_E",
    "Ground-1_F",
    "Ground-1_G",
    "Ground-1_H",
  }

  local function randInt(min, max)
    -- Prefer engine-provided RNG if available (often seeded by DCS)
    if type(math.random) == "function" then
      return math.random(min, max)
    end
    -- Fallback: deterministic but varies with time (if time is non-zero)
    local t = 0
    if timer and timer.getAbsTime then t = timer.getAbsTime() elseif timer and timer.getTime then t = timer.getTime() end
    local x = math.floor((t * 100000) % 2147483647)
    if x < 1 then x = 1234567 end
    x = (1103515245 * x + 12345) % 2147483647
    return (x % (max - min + 1)) + min
  end

  local pickIdx  = randInt(1, #candidates)
  local pickName = candidates[pickIdx]

  local g = Group.getByName(pickName)
  if g then
    Group.activate(g)
    trigger.action.setUserFlag(9200, pickIdx)

    -- DEBUG: confirma qué salió
    trigger.action.outText(string.format("[AT4][DEBUG] SA-2 PICKED: %s (idx=%d)", pickName, pickIdx), 10)
  else
    trigger.action.outText("[AT4] ERROR: SA-2 group not found: " .. tostring(pickName), 12)
  end
end

-- =========================
-- 2) SEAD EVALUATOR (Fan Song + Flat Face must be destroyed)
-- =========================
AT4_SEAD = AT4_SEAD or {}
AT4_SEAD.targets = {
  FAN_SONG  = "Ground-1-1",   -- SNR_75V (Fan Song)
  FLAT_FACE = "Ground-1-10",  -- P-19 (Flat Face)
}
AT4_SEAD.state = {
  fanDown = false,
  flatDown = false,
  completed = false,
}
AT4_SEAD.FLAG_SEAD_COMPLETE = 9001

local function _at4_sead_check()
  if AT4_SEAD.state.completed then return end
  if AT4_SEAD.state.fanDown and AT4_SEAD.state.flatDown then
    AT4_SEAD.state.completed = true
    _setFlag(AT4_SEAD.FLAG_SEAD_COMPLETE, 1)
    _msg("[AT4] SEAD COMPLETE (Fan Song + Flat Face destroyed)", 8)
  end
end

local AT4_SEAD_Handler = {}
function AT4_SEAD_Handler:onEvent(event)
  if not event then return end
  if event.id ~= world.event.S_EVENT_DEAD then return end
  if not event.initiator then return end

  local deadName = event.initiator:getName()
  if not deadName then return end

  if deadName == AT4_SEAD.targets.FAN_SONG then
    AT4_SEAD.state.fanDown = true
    _msg("[AT4] Fan Song destroyed", 6)
    _at4_sead_check()
    return
  end

  if deadName == AT4_SEAD.targets.FLAT_FACE then
    AT4_SEAD.state.flatDown = true
    _msg("[AT4] Flat Face destroyed", 6)
    _at4_sead_check()
    return
  end
end
world.addEventHandler(AT4_SEAD_Handler)

-- =========================
-- 3) TOT SYSTEM (1 TOT per mission, unpredictable, includes AAR reserve)
-- =========================
AT4_TOT = AT4_TOT or {}

AT4_TOT.cfg = {
  coalitionSide = coalition.side.BLUE,

  zoneHoldFixName = "ZONE_HOLD_FIX",   -- create a small zone for the holding fix/orbit reference

  -- Mission timing model
  holdToImpactSec      = 7*60 + 30,    -- 07:30 (HOLD -> IMPACT)
  waitMinSec           = 2*60,         -- MIN holding wait (your request)
  waitMaxSec           = 10*60,        -- MAX holding wait

  -- AAR reserves (your numbers)
  minAarFromRampSec    = 30*60,        -- if TOT announced while on ramp / before takeoff
  minAarFromAirSec     = 15*60,        -- if TOT announced while airborne (before AAR complete)

  -- TOT announcement window (unpredictable)
  announceEarliestSec  = 60,           -- earliest random announce (T+1:00)
  announceLatestSec    = 25*60,        -- latest time; after this it forces announce
  announceChancePct    = 2,            -- % chance per second tick inside the window

  -- Flags for your debrief (optional)
  FLAG_TOT_ANNOUNCED   = 9100,
  FLAG_AAR_COMPLETE    = 9102,
}

AT4_TOT.state = {
  totGenerated = false,
  totSec = nil,
  totAnnounced = false,

  aarCompleted = false,
  aarCompletedBy = nil,
}

local function _getFirstPlayerUnit()
  local players = coalition.getPlayers(AT4_TOT.cfg.coalitionSide) or {}
  for _,u in ipairs(players) do
    if u and u:isExist() then return u end
  end
  return nil
end

local function _getGS(u)
  local v = u:getVelocity()
  return math.sqrt((v.x or 0)^2 + (v.z or 0)^2) -- m/s, 2D
end

local function _isOnGround(u)
  -- heuristic: very low GS and very low AGL
  local gs = _getGS(u)
  local p = u:getPoint()
  local ground = land.getHeight({x=p.x, y=p.z}) or 0
  local agl = p.y - ground
  return (gs < 5) and (agl < 10)
end

local function _etaToZoneSec(u, z)
  if not u or not u:isExist() or not z then return 0 end
  local p = u:getPoint()
  local d = _dist2D(p, z.point)
  local gs = _getGS(u)
  if gs < 30 then gs = 80 end -- avoid absurd ETAs while taxiing
  return d / gs
end

local function _aarReserveSec(u)
  if _isOnGround(u) then return AT4_TOT.cfg.minAarFromRampSec end
  return AT4_TOT.cfg.minAarFromAirSec
end

-- ---- F10 Menu (coalition BLUE) ----
AT4_TOT.menu = AT4_TOT.menu or { root = nil }

local function _buildMenu()
  if AT4_TOT.menu.root then return end

  AT4_TOT.menu.root = missionCommands.addSubMenuForCoalition(AT4_TOT.cfg.coalitionSide, "AT-4 (E111)")

  missionCommands.addCommandForCoalition(AT4_TOT.cfg.coalitionSide, "AAR COMPLETE", AT4_TOT.menu.root, function()
    if AT4_TOT.state.aarCompleted then
      _msg("[AT4] AAR already marked COMPLETE", 6)
      return
    end

    local u = _getFirstPlayerUnit()
    local who = (u and u:isExist() and u:getName()) or "UNKNOWN"
    AT4_TOT.state.aarCompleted = true
    AT4_TOT.state.aarCompletedBy = who
    _setFlag(AT4_TOT.cfg.FLAG_AAR_COMPLETE, 1)
    _msg("[AT4] AAR marked COMPLETE", 6) -- generic (no extra hints)
  end)

  missionCommands.addCommandForCoalition(AT4_TOT.cfg.coalitionSide, "TOT STATUS", AT4_TOT.menu.root, function()
    if not AT4_TOT.state.totGenerated then
      _msg("[AT4] TOT not generated yet.", 6)
      return
    end
    local now = _now()
    _msg(string.format("[AT4] TOT: %s | Time to TOT: %s | AAR complete: %s",
      _formatClock(AT4_TOT.state.totSec),
      _formatDelta(AT4_TOT.state.totSec - now),
      tostring(AT4_TOT.state.aarCompleted)), 10)
  end)
end

-- ---- TOT generation & announce ----
function AT4_TOT.generateTOT()
  if AT4_TOT.state.totGenerated then return end

  local u = _getFirstPlayerUnit()
  if not u then return end

  local now = _now()
  local wait = AT4_RNG.int(AT4_TOT.cfg.waitMinSec, AT4_TOT.cfg.waitMaxSec)

  local reserve = 0

  if not AT4_TOT.state.aarCompleted then
    -- Reserve time to get AAR done before holding management
    reserve = _aarReserveSec(u)
  else
    -- After AAR complete, optionally include ETA to holding fix (small)
    local holdFix = _getZone(AT4_TOT.cfg.zoneHoldFixName)
    if holdFix then
      reserve = _etaToZoneSec(u, holdFix)
    else
      reserve = 0
    end
  end

  AT4_TOT.state.totSec = now + reserve + wait + AT4_TOT.cfg.holdToImpactSec
  AT4_TOT.state.totGenerated = true
end

function AT4_TOT.announceTOT()
  if AT4_TOT.state.totAnnounced then return end

  if not AT4_TOT.state.totGenerated then
    AT4_TOT.generateTOT()
    if not AT4_TOT.state.totGenerated then return end
  end

  AT4_TOT.state.totAnnounced = true
  _setFlag(AT4_TOT.cfg.FLAG_TOT_ANNOUNCED, 1)

  local now = _now()
  _msg("[AT4] TOT for TGT-1: " .. _formatClock(AT4_TOT.state.totSec) .. " (mission time).", 10)
  _msg("[AT4] Reference: HOLD->IMPACT = 07:30. Holding wait 02:00..10:00. No repeats.", 10)
  _msg("[AT4] Time to TOT now: " .. _formatDelta(AT4_TOT.state.totSec - now), 10)
end

-- ---- Scheduler ----
function AT4_TOT.scheduler()
  _buildMenu()

  local now = _now()

  if not AT4_TOT.state.totAnnounced then
    if now >= AT4_TOT.cfg.announceEarliestSec and now <= AT4_TOT.cfg.announceLatestSec then
      if not AT4_TOT.state.totGenerated then AT4_TOT.generateTOT() end
      if AT4_RNG.pct(AT4_TOT.cfg.announceChancePct) then
        AT4_TOT.announceTOT()
      end
    end

    if (not AT4_TOT.state.totAnnounced) and now > AT4_TOT.cfg.announceLatestSec then
      if not AT4_TOT.state.totGenerated then AT4_TOT.generateTOT() end
      AT4_TOT.announceTOT()
    end
  end

  return now + 1
end

timer.scheduleFunction(function() return AT4_TOT.scheduler() end, {}, _now() + 1)

-- =========================
-- 4) STARTUP MESSAGE
-- =========================
_msg("[AT4] Scripts armed: SA-2 random + SEAD evaluator + TOT system. Use F10 -> AT-4 (E111) -> AAR COMPLETE when done.", 10)