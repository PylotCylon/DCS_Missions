-- =========================
-- ATC_AI PoC - Kutaisi (Caucasus)
-- Autonomous Military ATC + Recovery Manager + Academy A/B (Overhead-only)
-- No external libs required (NO MOOSE/MIST).
--
-- MP-safe callbacks: missionCommands callbacks do NOT use Group.getById().
-- Each F10 menu is bound to leader unitName at creation time.
-- =========================

ATC_AI = {
  cfg = {
    airbaseName = "Kutaisi",
    coalitionSide = coalition.side.BLUE,

    sepSeconds = 75,         -- runway separation timer
    contactCooldown = 10,    -- min seconds between ATC calls to same unit

    -- Fuel thresholds use unit:getFuel() fraction 0..1 (works across modules)
    fuelCritical = 0.12,
    fuelLow      = 0.20,
    fuelMed      = 0.28,

    patternAGL_ft = 1500,    -- suggested pattern altitude AGL
    overheadInitialNM = 5,   -- "hold/report initial"
  },

  state = {
    activeRWY = "07",
    rwyOccupiedUntil = 0,

    inbound = {},     -- { unitName, prio, reqType, ts, lastCall, cleared }
    outbound = {},

    menus = {},       -- groupId -> true
    groupLeaderUnitName = {}, -- groupId -> leaderUnitName (MP-safe)

    metrics = {
      clearLand = 0,
      clearTakeoff = 0,
      holds = 0,
      emergencies = 0,
      cancels = 0,
      rtbReq = 0,
      taxiReq = 0,
      tkofReq = 0,
    }
  }
}

-- -------- utils --------
local function tnow() return timer.getTime() end
local function ft(m) return m * 3.28084 end

local function logi(msg)
  env.info("[ATC_AI] " .. msg)
end

local function msgToUnit(u, text, dur)
  dur = dur or 10
  if u and u:isExist() then
    trigger.action.outTextForUnit(u:getID(), text, dur)
  else
    trigger.action.outText(text, dur)
  end
end

local function msgToGroup(groupId, text, dur)
  dur = dur or 10
  trigger.action.outTextForGroup(groupId, text, dur)
end

local function getUnitByNameSafe(name)
  local u = Unit.getByName(name)
  if u and u:isExist() then return u end
  return nil
end

local function runwayFree()
  return tnow() > (ATC_AI.state.rwyOccupiedUntil or 0)
end

local function occupyRunway(seconds)
  ATC_AI.state.rwyOccupiedUntil = math.max(ATC_AI.state.rwyOccupiedUntil or 0, tnow() + seconds)
end

local function removeFromQueue(q, unitName)
  for i = #q, 1, -1 do
    if q[i].unitName == unitName then table.remove(q, i) end
  end
end

local function upsert(queue, unitName, prio, reqType)
  for _,e in ipairs(queue) do
    if e.unitName == unitName then
      e.prio = prio or e.prio
      e.reqType = reqType or e.reqType
      e.ts = e.ts or tnow()
      e.lastCall = e.lastCall or 0
      e.cleared = e.cleared or false
      return e
    end
  end
  local e = {
    unitName = unitName,
    prio = prio or 1,
    reqType = reqType or "NEW",
    ts = tnow(),
    lastCall = 0,
    cleared = false
  }
  table.insert(queue, e)
  return e
end

local function sortQueue(q)
  table.sort(q, function(a,b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    return (a.ts or 0) < (b.ts or 0)
  end)
end

local function getAirbasePointAndElev()
  local ab = Airbase.getByName(ATC_AI.cfg.airbaseName)
  if not ab then return nil, 0 end
  local p = ab:getPoint()
  local elev_m = land.getHeight({x=p.x, y=p.z}) or 0
  return p, elev_m
end

local function computeActiveRunway07_25()
  local p, elev = getAirbasePointAndElev()
  if not p then return ATC_AI.state.activeRWY or "07" end

  local w = atmosphere.getWind({x=p.x, y=elev + 10, z=p.z})
  local wx, wz = w.x or 0, w.z or 0

  if math.abs(wx) < 0.5 and math.abs(wz) < 0.5 then
    return ATC_AI.state.activeRWY or "07"
  end

  local toRad = math.atan2(wx, wz)
  local toDeg = (math.deg(toRad) + 360) % 360
  local fromDeg = (toDeg + 180) % 360

  local function angDiff(a,b)
    local d = math.abs(a-b) % 360
    return (d > 180) and (360-d) or d
  end

  local d07 = angDiff(fromDeg, 70)
  local d25 = angDiff(fromDeg, 250)

  return (d07 <= d25) and "07" or "25"
end

local function computePriority(u, isEmergency)
  if isEmergency then return 6 end

  local fuel = u:getFuel() or 1.0
  local p = 2
  if fuel < ATC_AI.cfg.fuelCritical then p = 5
  elseif fuel < ATC_AI.cfg.fuelLow then p = 4
  elseif fuel < ATC_AI.cfg.fuelMed then p = 3
  else p = 2 end

  local desc = u:getDesc()
  if desc and desc.life and u:getLife() and u:getLife() < 0.6 * desc.life then
    p = math.max(p, 5)
  end

  return p
end

local function statusTextSimple(u)
  local fuel = u:getFuel() or 0
  local fuelPct = math.floor(fuel * 100 + 0.5)
  local life = u:getLife() or 0
  local rwy = tostring(ATC_AI.state.activeRWY)
  local freeIn = math.max(0, math.ceil((ATC_AI.state.rwyOccupiedUntil or 0) - tnow()))
  return string.format("RWY %s | Fuel %d%% | Life %.0f | RWY free in %ds", rwy, fuelPct, life, freeIn)
end

-- -------- clearances --------
local function issueLanding(entry)
  local u = getUnitByNameSafe(entry.unitName); if not u then return end
  if (tnow() - (entry.lastCall or 0)) < ATC_AI.cfg.contactCooldown then return end

  local _, elev = getAirbasePointAndElev()
  local patMSL_ft = ft(elev) + ATC_AI.cfg.patternAGL_ft

  if runwayFree() then
    msgToUnit(u, string.format(
      "[ATC_AI Kutaisi] %s: CLEARED TO LAND RWY %s. Pattern %d ft MSL. Report FINAL.",
      entry.unitName, ATC_AI.state.activeRWY, math.floor(patMSL_ft + 0.5)
    ), 10)
    occupyRunway(ATC_AI.cfg.sepSeconds)
    entry.cleared = true
    ATC_AI.state.metrics.clearLand = ATC_AI.state.metrics.clearLand + 1
    logi("LAND CLR -> " .. entry.unitName)
  else
    msgToUnit(u, string.format(
      "[ATC_AI Kutaisi] %s: CONTINUE INBOUND. HOLD %dNM INITIAL, expect clearance in %ds.",
      entry.unitName, ATC_AI.cfg.overheadInitialNM, math.ceil((ATC_AI.state.rwyOccupiedUntil or 0) - tnow())
    ), 10)
    ATC_AI.state.metrics.holds = ATC_AI.state.metrics.holds + 1
  end

  entry.lastCall = tnow()
end

local function issueTakeoff(entry)
  local u = getUnitByNameSafe(entry.unitName); if not u then return end
  if (tnow() - (entry.lastCall or 0)) < ATC_AI.cfg.contactCooldown then return end

  if runwayFree() then
    msgToUnit(u, string.format(
      "[ATC_AI Kutaisi] %s: LINE UP AND WAIT RWY %s. CLEARED FOR TAKEOFF. Maintain RWY HDG.",
      entry.unitName, ATC_AI.state.activeRWY
    ), 10)
    occupyRunway(ATC_AI.cfg.sepSeconds)
    entry.cleared = true
    ATC_AI.state.metrics.clearTakeoff = ATC_AI.state.metrics.clearTakeoff + 1
    logi("TKOF CLR -> " .. entry.unitName)
  else
    msgToUnit(u, string.format(
      "[ATC_AI Kutaisi] %s: HOLD SHORT RWY %s. Traffic on runway, expect %ds.",
      entry.unitName, ATC_AI.state.activeRWY,
      math.ceil((ATC_AI.state.rwyOccupiedUntil or 0) - tnow())
    ), 10)
    ATC_AI.state.metrics.holds = ATC_AI.state.metrics.holds + 1
  end

  entry.lastCall = tnow()
end

-- -------- scheduler policy --------
local function scheduler()
  ATC_AI.state.activeRWY = computeActiveRunway07_25()

  local function refreshQueue(q)
    for _,e in ipairs(q) do
      local u = getUnitByNameSafe(e.unitName)
      if u then
        local isEmerg = (e.reqType == "EMERGENCY")
        e.prio = computePriority(u, isEmerg)
      end
    end
    sortQueue(q)
  end

  refreshQueue(ATC_AI.state.inbound)
  refreshQueue(ATC_AI.state.outbound)

  local topIn = ATC_AI.state.inbound[1]
  local topOut = ATC_AI.state.outbound[1]

  if topIn and not topOut then
    issueLanding(topIn)
  elseif topOut and not topIn then
    issueTakeoff(topOut)
  elseif topIn and topOut then
    if topIn.prio >= 4 then
      issueLanding(topIn)
    else
      if runwayFree() then issueTakeoff(topOut) else issueLanding(topIn) end
    end
  end

  return tnow() + 1.0
end

-- -------- Unit binding helper (no Group.getById) --------
local function getBoundUnitForGroup(groupId)
  local unitName = ATC_AI.state.groupLeaderUnitName[groupId]
  if not unitName then return nil, "no unitName bound" end
  local u = Unit.getByName(unitName)
  if not u or not u:isExist() then return nil, "bound unit not found" end
  return u, nil
end

-- -------- F10 Menus (MP-safe) --------
local function addMenusForGroup(groupId, leaderUnitName)
  if ATC_AI.state.menus[groupId] then return end
  ATC_AI.state.menus[groupId] = true
  ATC_AI.state.groupLeaderUnitName[groupId] = leaderUnitName

  local root = missionCommands.addSubMenuForGroup(groupId, "ATC_AI Kutaisi")

  missionCommands.addCommandForGroup(groupId, "Request Taxi", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      msgToGroup(groupId, "[ATC_AI] Taxi: " .. tostring(err) .. " (re-slot).", 10)
      return
    end

    local name = u:getName()
    removeFromQueue(ATC_AI.state.inbound, name)
    upsert(ATC_AI.state.outbound, name, computePriority(u, false), "REQ_TAXI")
    ATC_AI.state.metrics.taxiReq = ATC_AI.state.metrics.taxiReq + 1

    msgToUnit(u, "[ATC_AI] Taxi request received. Stand by for sequencing.", 8)
    logi("REQ_TAXI " .. name)
  end)

  missionCommands.addCommandForGroup(groupId, "Request Takeoff", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      msgToGroup(groupId, "[ATC_AI] Takeoff: " .. tostring(err) .. " (re-slot).", 10)
      return
    end

    local name = u:getName()
    removeFromQueue(ATC_AI.state.inbound, name)
    upsert(ATC_AI.state.outbound, name, computePriority(u, false), "REQ_TKOF")
    ATC_AI.state.metrics.tkofReq = ATC_AI.state.metrics.tkofReq + 1

    msgToUnit(u, "[ATC_AI] Takeoff request received. Hold short and await clearance.", 8)
    logi("REQ_TKOF " .. name)
  end)

  missionCommands.addCommandForGroup(groupId, "Request RTB / Inbound", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      msgToGroup(groupId, "[ATC_AI] RTB: " .. tostring(err) .. " (re-slot).", 10)
      return
    end

    local name = u:getName()
    removeFromQueue(ATC_AI.state.outbound, name)
    upsert(ATC_AI.state.inbound, name, computePriority(u, false), "REQ_RTB")
    ATC_AI.state.metrics.rtbReq = ATC_AI.state.metrics.rtbReq + 1

    msgToUnit(u, "[ATC_AI] Inbound request received. Proceed to initial and await clearance.", 8)
    logi("REQ_RTB " .. name)
  end)

  missionCommands.addCommandForGroup(groupId, "Declare Emergency (Priority)", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      msgToGroup(groupId, "[ATC_AI] Emergency: " .. tostring(err) .. " (re-slot).", 10)
      return
    end

    local name = u:getName()
    removeFromQueue(ATC_AI.state.outbound, name)
    upsert(ATC_AI.state.inbound, name, computePriority(u, true), "EMERGENCY")
    ATC_AI.state.metrics.emergencies = ATC_AI.state.metrics.emergencies + 1

    msgToUnit(u, "[ATC_AI] EMERGENCY declared. You are now priority inbound.", 10)
    logi("EMERGENCY " .. name)
  end)

  missionCommands.addCommandForGroup(groupId, "Status", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      trigger.action.outText("[ATC_AI] Status: " .. tostring(err) .. " (re-slot).", 10)
      return
    end
    msgToUnit(u, "[ATC_AI] " .. statusTextSimple(u), 10)
    logi("STATUS " .. tostring(u:getName()))
  end)

  missionCommands.addCommandForGroup(groupId, "Cancel Request (Remove from queues)", root, function()
    local u, err = getBoundUnitForGroup(groupId)
    if not u then
      msgToGroup(groupId, "[ATC_AI] Cancel: " .. tostring(err) .. " (re-slot).", 10)
      return
    end

    local name = u:getName()
    removeFromQueue(ATC_AI.state.inbound, name)
    removeFromQueue(ATC_AI.state.outbound, name)
    ATC_AI.state.metrics.cancels = ATC_AI.state.metrics.cancels + 1

    msgToUnit(u, "[ATC_AI] Request cancelled. You are removed from sequencing.", 8)
    logi("CANCEL " .. name)
  end)
end

local function bootstrapMenus()
  local players = coalition.getPlayers(ATC_AI.cfg.coalitionSide) or {}
  for _,u in ipairs(players) do
    if u and u:isExist() then
      local g = u:getGroup()
      if g then
        addMenusForGroup(g:getID(), u:getName())
      end
    end
  end
  return tnow() + 5.0
end

-- -------- event handler (auto-menu + cleanup) --------
ATC_AI_EH = {}
function ATC_AI_EH:onEvent(event)
  if not event or not event.initiator then return end
  local u = event.initiator
  if not u or not u:isExist() then return end

  local g = u:getGroup()
  if g then
    local gid = g:getID()
    if not ATC_AI.state.menus[gid] then
      addMenusForGroup(gid, u:getName())
    end
  end

  local name = u:getName()

  if event.id == world.event.S_EVENT_TAKEOFF then
    removeFromQueue(ATC_AI.state.outbound, name)
    logi("TAKEOFF " .. name)
  elseif event.id == world.event.S_EVENT_LAND then
    removeFromQueue(ATC_AI.state.inbound, name)
    logi("LAND " .. name)
  elseif event.id == world.event.S_EVENT_CRASH or event.id == world.event.S_EVENT_EJECT then
    removeFromQueue(ATC_AI.state.inbound, name)
    removeFromQueue(ATC_AI.state.outbound, name)
    logi("REMOVE (CRASH/EJECT) " .. name)
  end
end
world.addEventHandler(ATC_AI_EH)

-- -------- start schedulers --------
timer.scheduleFunction(function() return scheduler() end, {}, tnow() + 1.0)
timer.scheduleFunction(function() return bootstrapMenus() end, {}, tnow() + 2.0)

trigger.action.outText("[ATC_AI] Script loaded (Kutaisi). Open F10 > ATC_AI Kutaisi.", 10)
logi("ATC_AI PoC started for airbase " .. ATC_AI.cfg.airbaseName)

-- =========================
-- ACADEMY MODE (A+B): Overhead-only feedback + grading
-- =========================
ATC_AI.academy = {
  enabled = true,

  -- Overhead gate (1500 AGL target with +/-100ft window)
  overhead = { distNM_min = 4.0, distNM_max = 6.0, hdg_tol = 20, agl_min = 1400, agl_max = 1600 },

  -- Downwind REAL (side+spacing) + speed gate
  downwind = {
    minNM = 0.6,
    maxNM = 2.0,
    sideLockSeconds = 20,
    abeamFracMin = 0.45,
    abeamFracMax = 0.85
  },
  downwindSpeed = { min = 200, max = 250 },

  -- Initial speed policy
  initial = { target = 300, fast = 320, slow = 260 },
  penalties = {
    initialFast = { {320,339,5}, {340,359,10}, {360,999,15} },
    initialSlow = nil
  },

  -- Kutaisi thresholds from user (decimal degrees) + detection zone
  threshold = {
    rwy07 = { lat = 42 + (10.545/60), lon = 42 + (27.985/60) },
    rwy25 = { lat = 42 + (10.768/60), lon = 42 + (29.762/60) },
    zoneNM = 0.25,
    hdgTol = 25
  },

  -- Break rules: valid from 50% to 102% (late margin +2%) + level break penalty per 100ft
  breakRules = {
    minFrac = 0.50,
    maxFrac = 1.00,
    corridorM = 180,
    turnHdgDelta = 25,
    alignTol = 15,
    penaltyEarly = 10,
    penaltyLate  = 10,

    targetAGL_ft = 1500,
    penaltyPer100ft = 2,
    maxAltPenalty = 30,

    minDropBy180_ft = 200, -- descent progressive check at 180
    noDescentPenalty = 10
  },

  -- 180/90/FINAL system
  final = {
    hdg_tol = 8,
    centerlineMaxM = 120,
    agl_max = 650,
    minSecondsStable = 6,
  },

  base = {
    hdg90_tol = 20,
    minTurnRateDeg = 2,
    posMinFactor = 0.30,
    posMaxFactor = 0.80
  },

  -- Penalties
  finalPenalties = {
    overshootM = 250,
    overshootPenalty = 10,
    overshootBigM = 400,
    overshootBigPenalty = 20
  },

  bankRules = {
    maxBank90 = 60,
    penaltyPer5deg = 2,
    maxPenalty = 20
  },

  flatPatternRules = {
    at90_maxAGL_ft  = 900,
    penaltyPer100ft = 2,
    maxPenalty = 20
  },

  -- Score weights (sum 100)
  weights = { overhead = 25, breakEvt = 20, downwind = 20, final = 35 },

  students = {},
  lastFeedback = {},

  _thr07 = nil,
  _thr25 = nil,
  _rwy = nil
}

local function _degDiff(a,b)
  local d = math.abs((a - b) % 360)
  return (d > 180) and (360 - d) or d
end
local function _nmFromMeters(m) return m / 1852 end
local function _ktsFromMps(v) return v * 1.94384 end

local function _distance2D(p1,p2)
  local dx = p1.x - p2.x
  local dz = p1.z - p2.z
  return math.sqrt(dx*dx + dz*dz)
end

local function _getRunwayHeadingDeg()
  if ATC_AI.state.activeRWY == "07" then return 70 else return 250 end
end

local function _getTrackDegFromVelocity(v)
  local hdg = math.deg(math.atan2(v.x, v.z))
  return (hdg + 360) % 360
end

local function _getAirbaseRef()
  local ab = Airbase.getByName(ATC_AI.cfg.airbaseName)
  if not ab then return nil, 0 end
  local p = ab:getPoint()
  local elev = land.getHeight({x=p.x, y=p.z}) or 0
  return p, elev
end

local function _ensureStudent(name)
  if not ATC_AI.academy.students[name] then
    ATC_AI.academy.students[name] = {
      overheadOK = false,
      breakDone = false,
      downwindOK = false,
      finalStable = false,
      landed = false,

      -- phase markers
      at180 = false,
      at90 = false,

      finalStableSeconds = 0,

      score = 0,
      notes = {},

      -- per-recovery controls
      recoveryArmed = false,
      initialFastPenalizedThisRecovery = false,
      breakPenalizedThisRecovery = false,
      breakAltPenalizedThisRecovery = false,
      overshootPenalizedThisRecovery = false,
      bankPenalizedThisRecovery = false,
      descentPenalizedThisRecovery = false,
      flatPenalizedThisRecovery = false,

      wasAlignedOnRunway = false,
      breakTime = nil,
      breakAGL_ft = nil,

      patternSide = nil,   -- "L" or "R"
      prevTrack = nil,
      prevLatAbsM = nil,
    }
  end
  return ATC_AI.academy.students[name]
end

local function _addNote(s, note)
  s.notes[#s.notes+1] = note
end

local function _throttledFeedback(unit, unitName, text, minGap)
  minGap = minGap or 4
  local t = timer.getTime()
  local last = ATC_AI.academy.lastFeedback[unitName] or 0
  if (t - last) >= minGap then
    msgToUnit(unit, "[ACADEMY] " .. text, 5)
    ATC_AI.academy.lastFeedback[unitName] = t
  end
end

local function _turnRateDeg(prev, current)
  if not prev then return 0 end
  local d = (current - prev + 540) % 360 - 180
  return d
end

local function _bankDeg(unit)
  local p = unit:getPosition()
  if not p or not p.x or not p.y then return 0 end
  local roll = math.deg(math.atan2(p.x.y or 0, p.y.y or 1))
  return math.abs(roll)
end

local function _runwayDirVector(rwyHdgDeg)
  local rad = math.rad(rwyHdgDeg)
  return { x = math.sin(rad), z = math.cos(rad) }
end

local function _signedLateralMeters(pos, startP, dir)
  local dx = pos.x - startP.x
  local dz = pos.z - startP.z
  return (dir.x * dz - dir.z * dx)
end

local function _LLtoPoint(lat, lon)
  local ok, p = pcall(function() return coord.LLtoLO(lat, lon) end)
  if ok and p then return p end

  local ok2, p2 = pcall(function() return coord.LLtoLO({lat=lat, lon=lon}) end)
  if ok2 and p2 then return p2 end

  env.info(string.format("[ATC_AI][ACADEMY] LLtoPoint failed for lat=%.6f lon=%.6f", lat, lon))
  return nil
end

local function _initThresholdPoints()
  if ATC_AI.academy._thr07 and ATC_AI.academy._thr25 and ATC_AI.academy._rwy then return end

  if not ATC_AI.academy._thr07 then
    ATC_AI.academy._thr07 = _LLtoPoint(ATC_AI.academy.threshold.rwy07.lat, ATC_AI.academy.threshold.rwy07.lon)
    if ATC_AI.academy._thr07 then env.info("[ATC_AI][ACADEMY] Threshold 07 point OK") end
  end

  if not ATC_AI.academy._thr25 then
    ATC_AI.academy._thr25 = _LLtoPoint(ATC_AI.academy.threshold.rwy25.lat, ATC_AI.academy.threshold.rwy25.lon)
    if ATC_AI.academy._thr25 then env.info("[ATC_AI][ACADEMY] Threshold 25 point OK") end
  end

  if ATC_AI.academy._thr07 and ATC_AI.academy._thr25 and not ATC_AI.academy._rwy then
    local a = ATC_AI.academy._thr07
    local b = ATC_AI.academy._thr25
    local vx = (b.x - a.x)
    local vz = (b.z - a.z)
    local len = math.sqrt(vx*vx + vz*vz)

    ATC_AI.academy._rwy = {
      a = a, b = b,
      vx = vx, vz = vz,
      len = len
    }
    env.info(string.format("[ATC_AI][ACADEMY] RWY geom OK. len=%.0fm", len))
  end
end

local function _projectAlongRunwayMeters(p, startP, vx, vz, len)
  local dx = p.x - startP.x
  local dz = p.z - startP.z
  local dot = dx*vx + dz*vz
  return dot / len
end

local function _distToCenterlineMeters(p, startP, vx, vz, len)
  local dx = p.x - startP.x
  local dz = p.z - startP.z
  local along = (dx*vx + dz*vz) / (len*len)
  local projx = startP.x + along*vx
  local projz = startP.z + along*vz
  local cx = p.x - projx
  local cz = p.z - projz
  return math.sqrt(cx*cx + cz*cz)
end

local function _gradeAndPrint(unit, unitName, s)
  if s.landed then return end
  s.landed = true

  local score = s.score
  local grade = (score >= 85) and "Q" or "NQ"

  local notes = ""
  if #s.notes > 0 then
    notes = " | Notes: " .. table.concat(s.notes, "; ")
  end

  msgToUnit(unit, string.format("[ACADEMY] FINAL GRADE: %s | Score: %d/100%s", grade, score, notes), 20)
  env.info(string.format("[ATC_AI][ACADEMY] %s Grade=%s Score=%d Notes=%s", unitName, grade, score, table.concat(s.notes, "; ")))
end

-- Grade on landing
ATC_AI_Academy_EH = {}
function ATC_AI_Academy_EH:onEvent(event)
  if not ATC_AI.academy.enabled then return end
  if not event or not event.initiator then return end
  local u = event.initiator
  if not u or not u:isExist() then return end

  if event.id == world.event.S_EVENT_LAND then
    local name = u:getName()
    local s = _ensureStudent(name)
    _gradeAndPrint(u, name, s)
  end
end
world.addEventHandler(ATC_AI_Academy_EH)

local function _academyMonitor()
  if not ATC_AI.academy.enabled then return timer.getTime() + 1 end

  _initThresholdPoints()

  local abPoint, abElev = _getAirbaseRef()
  if not abPoint then return timer.getTime() + 1 end

  local rwyHdg = _getRunwayHeadingDeg()

  for _,u in ipairs(coalition.getPlayers(ATC_AI.cfg.coalitionSide) or {}) do
    if u and u:isExist() then
      local name = u:getName()
      local s = _ensureStudent(name)

      -- DCS Lua 5.1: no goto. Envolvemos.
      if not s.landed then
        local pos = u:getPoint()
        local groundHere = land.getHeight({x=pos.x, y=pos.z}) or abElev
        local agl_ft = (pos.y - groundHere) * 3.28084

        local vel = u:getVelocity()
        local gs_kts = _ktsFromMps(math.sqrt(vel.x^2 + vel.z^2))
        local trk = _getTrackDegFromVelocity(vel)

        local distNM = _nmFromMeters(_distance2D(pos, abPoint))

        -- ===== Initial gate (arms a new recovery) =====
        local inInitialGate = (distNM >= ATC_AI.academy.overhead.distNM_min and distNM <= ATC_AI.academy.overhead.distNM_max)
                              and (_degDiff(trk, rwyHdg) <= ATC_AI.academy.overhead.hdg_tol)

        if inInitialGate and not s.recoveryArmed then
          s.recoveryArmed = true
          s.initialFastPenalizedThisRecovery = false
          s.breakPenalizedThisRecovery = false
          s.breakAltPenalizedThisRecovery = false
          s.overshootPenalizedThisRecovery = false
          s.bankPenalizedThisRecovery = false
          s.descentPenalizedThisRecovery = false
          s.flatPenalizedThisRecovery = false

          s.wasAlignedOnRunway = false
          s.breakTime = nil
          s.breakAGL_ft = nil
          s.patternSide = nil

          s.at180 = false
          s.at90 = false
          s.finalStable = false
          s.finalStableSeconds = 0
          s.prevTrack = nil
          s.prevLatAbsM = nil
        end

        if (not inInitialGate) and s.recoveryArmed then
          s.recoveryArmed = false
        end

        -- ===== Overhead window gate (1500 AGL +/-100) =====
        if not s.overheadOK then
          local okDist = (distNM >= ATC_AI.academy.overhead.distNM_min and distNM <= ATC_AI.academy.overhead.distNM_max)
          local okHdg  = (_degDiff(trk, rwyHdg) <= ATC_AI.academy.overhead.hdg_tol)
          local okAlt  = (agl_ft >= ATC_AI.academy.overhead.agl_min and agl_ft <= ATC_AI.academy.overhead.agl_max)

          if okDist and okHdg and okAlt then
            s.overheadOK = true
            s.score = s.score + ATC_AI.academy.weights.overhead
            _throttledFeedback(u, name, "Overhead OK (1500 AGL)", 2)
          else
            if okDist and okHdg and (agl_ft < ATC_AI.academy.overhead.agl_min) then
              _throttledFeedback(u, name, "Overhead LOW (target 1500 AGL)", 5)
            elseif okDist and okHdg and (agl_ft > ATC_AI.academy.overhead.agl_max) then
              _throttledFeedback(u, name, "Overhead HIGH (target 1500 AGL)", 5)
            end
          end
        end

        -- ===== Initial speed callout (informative) =====
        if inInitialGate and gs_kts >= ATC_AI.academy.initial.fast then
          _throttledFeedback(u, name, string.format("FAST (Initial %.0f kt, target %d)", gs_kts, ATC_AI.academy.initial.target), 5)
        end

        -- ===== Threshold FAST penalty (REAL thresholds, only once per recovery) =====
        local thrPoint = nil
        if ATC_AI.state.activeRWY == "07" then thrPoint = ATC_AI.academy._thr07 else thrPoint = ATC_AI.academy._thr25 end

        local inThresholdZone = false
        if thrPoint then
          local thrDistNM = (_distance2D(pos, thrPoint) / 1852)
          inThresholdZone = (thrDistNM <= ATC_AI.academy.threshold.zoneNM)
                            and (_degDiff(trk, rwyHdg) <= ATC_AI.academy.threshold.hdgTol)
        end

        if inThresholdZone and gs_kts >= ATC_AI.academy.initial.fast then
          if s.recoveryArmed and (not s.initialFastPenalizedThisRecovery) then
            local penalty = 5
            for _,band in ipairs(ATC_AI.academy.penalties.initialFast) do
              local lo, hi, pts = band[1], band[2], band[3]
              if gs_kts >= lo and gs_kts <= hi then penalty = pts break end
            end
            s.score = math.max(0, s.score - penalty)
            s.initialFastPenalizedThisRecovery = true
            _addNote(s, string.format("Threshold fast (-%d)", penalty))
            msgToUnit(u, string.format("[ACADEMY] Penalty: THRESHOLD FAST (-%d)", penalty), 6)
          end
        end

        -- ===== Break detection with runway window (50%..102%) + level break penalty per 100ft =====
        if s.overheadOK and (not s.breakDone) and ATC_AI.academy._rwy then
          local r = ATC_AI.academy._rwy

          local startP, vx, vz, len
          if ATC_AI.state.activeRWY == "07" then
            startP, vx, vz, len = r.a, r.vx, r.vz, r.len
          else
            startP, vx, vz, len = r.b, -r.vx, -r.vz, r.len
          end

          local alongM = _projectAlongRunwayMeters(pos, startP, vx, vz, len)
          local frac = alongM / len
          local offM = _distToCenterlineMeters(pos, startP, vx, vz, len)

          local inCorridor = (offM <= ATC_AI.academy.breakRules.corridorM)
          local inRunwaySpan = (frac >= -0.05 and frac <= 1.10)

          local aligned = (_degDiff(trk, rwyHdg) <= ATC_AI.academy.breakRules.alignTol)
          local turning = (_degDiff(trk, rwyHdg) >= ATC_AI.academy.breakRules.turnHdgDelta)

          if inCorridor and inRunwaySpan then
            s.wasAlignedOnRunway = s.wasAlignedOnRunway or aligned
          else
            s.wasAlignedOnRunway = false
          end

          if s.wasAlignedOnRunway and inCorridor and inRunwaySpan and turning then
            s.breakDone = true
            s.breakTime = timer.getTime()
            s.breakAGL_ft = agl_ft

            s.score = s.score + ATC_AI.academy.weights.breakEvt
            _throttledFeedback(u, name, "Break detected", 2)

            -- Window check (late margin +2%)
            local minF = ATC_AI.academy.breakRules.minFrac
            local maxF = ATC_AI.academy.breakRules.maxFrac + 0.02

            if frac < minF and not s.breakPenalizedThisRecovery then
              local pen = ATC_AI.academy.breakRules.penaltyEarly
              s.score = math.max(0, s.score - pen)
              s.breakPenalizedThisRecovery = true
              _addNote(s, string.format("Break early (%.0f%% RWY, -%d)", frac*100, pen))
              msgToUnit(u, string.format("[ACADEMY] Penalty: BREAK EARLY (%.0f%%, -%d)", frac*100, pen), 6)

            elseif frac > maxF and not s.breakPenalizedThisRecovery then
              local pen = ATC_AI.academy.breakRules.penaltyLate
              s.score = math.max(0, s.score - pen)
              s.breakPenalizedThisRecovery = true
              _addNote(s, string.format("Break late (%.0f%% RWY, -%d)", frac*100, pen))
              msgToUnit(u, string.format("[ACADEMY] Penalty: BREAK LATE (%.0f%%, -%d)", frac*100, pen), 6)

            else
              _throttledFeedback(u, name, string.format("Break OK (%.0f%% RWY)", frac*100), 3)
            end

            -- Level break altitude penalty (per 100ft) - once per recovery
            if not s.breakAltPenalizedThisRecovery then
              local diff = math.abs(agl_ft - ATC_AI.academy.breakRules.targetAGL_ft)
              local steps = math.floor(diff / 100)
              local penAlt = math.min(steps * ATC_AI.academy.breakRules.penaltyPer100ft,
                                      ATC_AI.academy.breakRules.maxAltPenalty)

              if penAlt > 0 then
                s.score = math.max(0, s.score - penAlt)
                _addNote(s, string.format("Break alt %.0fft AGL (-%d)", agl_ft, penAlt))
                msgToUnit(u, string.format("[ACADEMY] Penalty: BREAK ALT %.0fft (target %d, -%d)",
                  agl_ft, ATC_AI.academy.breakRules.targetAGL_ft, penAlt), 7)
              end

              s.breakAltPenalizedThisRecovery = true
            end
          end
        end

        -- ===== Downwind REAL: side + lateral spacing + speed gate =====
        if s.breakDone and (not s.downwindOK) and ATC_AI.academy._rwy then
          local r = ATC_AI.academy._rwy
          local dir = _runwayDirVector(rwyHdg)

          local startP
          if ATC_AI.state.activeRWY == "07" then startP = r.a else startP = r.b end

          local vx, vz, len
          if ATC_AI.state.activeRWY == "07" then vx, vz, len = r.vx, r.vz, r.len else vx, vz, len = -r.vx, -r.vz, r.len end
          local alongM = _projectAlongRunwayMeters(pos, startP, vx, vz, len)
          local frac = alongM / len

          local latSignedM = _signedLateralMeters(pos, startP, dir)
          local latNM = math.abs(latSignedM) / 1852

          -- Infer pattern side shortly after break
          if (not s.patternSide) and s.breakTime and ((timer.getTime() - s.breakTime) <= ATC_AI.academy.downwind.sideLockSeconds) then
            if math.abs(latSignedM) > 150 then
              s.patternSide = (latSignedM > 0) and "L" or "R"
              _throttledFeedback(u, name, "Pattern side locked: " .. s.patternSide, 6)
            end
          end

          local abeamOk = (frac >= ATC_AI.academy.downwind.abeamFracMin and frac <= ATC_AI.academy.downwind.abeamFracMax)
          local spacingOk = (latNM >= ATC_AI.academy.downwind.minNM and latNM <= ATC_AI.academy.downwind.maxNM)
          local speedOk = (gs_kts >= ATC_AI.academy.downwindSpeed.min and gs_kts <= ATC_AI.academy.downwindSpeed.max)

          local sideOk = true
          if s.patternSide then
            local curSide = (latSignedM > 0) and "L" or "R"
            sideOk = (curSide == s.patternSide)
          end

          if abeamOk and spacingOk and speedOk and sideOk then
            s.downwindOK = true
            s.score = s.score + ATC_AI.academy.weights.downwind
            _throttledFeedback(u, name, string.format("Downwind OK (%s, %.2fNM, %.0f kt)", tostring(s.patternSide or "?"), latNM, gs_kts), 3)
          else
            if abeamOk then
              if not spacingOk then
                _throttledFeedback(u, name, string.format("Downwind SPACING %.2fNM (need %.1f–%.1f)", latNM,
                  ATC_AI.academy.downwind.minNM, ATC_AI.academy.downwind.maxNM), 6)
              end
              if not speedOk then
                _throttledFeedback(u, name, string.format("Downwind SPEED %.0f kt (need %d–%d)", gs_kts,
                  ATC_AI.academy.downwindSpeed.min, ATC_AI.academy.downwindSpeed.max), 6)
              end
              if s.patternSide and not sideOk then
                _throttledFeedback(u, name, "Wrong side of pattern", 6)
              end
            end
          end
        end

        -- ===== 180 / 90 / FINAL GEOMETRIC SYSTEM (with penalties) =====
        if ATC_AI.academy._rwy then
          local r = ATC_AI.academy._rwy

          local vx, vz, len, startP
          if ATC_AI.state.activeRWY == "07" then
            vx, vz, len = r.vx, r.vz, r.len
            startP = r.a
          else
            vx, vz, len = -r.vx, -r.vz, r.len
            startP = r.b
          end

          local alongM = _projectAlongRunwayMeters(pos, startP, vx, vz, len)
          local frac = alongM / len

          local dir = _runwayDirVector(rwyHdg)
          local latSignedM = _signedLateralMeters(pos, startP, dir)
          local latAbsM = math.abs(latSignedM)
          local latNM = latAbsM / 1852

          -- closing detection
          local closing = false
          if s.prevLatAbsM then
            closing = (latAbsM < (s.prevLatAbsM - 10))
          end
          s.prevLatAbsM = latAbsM

          -- turn rate
          local turnRate = _turnRateDeg(s.prevTrack, trk)
          s.prevTrack = trk

          -- ===== 180 =====
          if s.downwindOK and (not s.at180) then
            local abeamOk = (frac >= ATC_AI.academy.downwind.abeamFracMin and frac <= ATC_AI.academy.downwind.abeamFracMax)
            if abeamOk then
              s.at180 = true
              _throttledFeedback(u, name, "180", 3)

              -- Descent progressive check at 180 (once per recovery)
              if s.recoveryArmed and (not s.descentPenalizedThisRecovery) and s.breakAGL_ft then
                local drop = s.breakAGL_ft - agl_ft
                if drop < ATC_AI.academy.breakRules.minDropBy180_ft then
                  local pen = ATC_AI.academy.breakRules.noDescentPenalty
                  s.score = math.max(0, s.score - pen)
                  s.descentPenalizedThisRecovery = true
                  _addNote(s, string.format("No descent by 180 (-%d)", pen))
                  msgToUnit(u, string.format("[ACADEMY] Penalty: NO DESCENT by 180 (drop %.0fft, -%d)", drop, pen), 7)
                end
              end
            end
          end

          -- ===== 90 (only if turning TOWARDS runway, closing, and position gate) =====
          if s.at180 and (not s.at90) then
            local hdgDiff90 = math.abs(_degDiff(trk, (rwyHdg + 90) % 360))
            local turnOk = (math.abs(turnRate) >= ATC_AI.academy.base.minTurnRateDeg)

            local dirOk = true
            if s.patternSide == "L" then
              dirOk = (turnRate < 0)
            elseif s.patternSide == "R" then
              dirOk = (turnRate > 0)
            end

            local posMinNM = ATC_AI.academy.downwind.minNM * ATC_AI.academy.base.posMinFactor
            local posMaxNM = ATC_AI.academy.downwind.maxNM * ATC_AI.academy.base.posMaxFactor
            local pos90Ok = (latNM >= posMinNM and latNM <= posMaxNM)

            if hdgDiff90 <= ATC_AI.academy.base.hdg90_tol and turnOk and dirOk and closing and pos90Ok then
              s.at90 = true
              _throttledFeedback(u, name, string.format("90 (lat %.2fNM)", latNM), 3)

              -- Bank penalty at 90 (once per recovery)
              if s.recoveryArmed and (not s.bankPenalizedThisRecovery) then
                local bank = _bankDeg(u)
                local maxB = ATC_AI.academy.bankRules.maxBank90
                if bank > maxB then
                  local over = bank - maxB
                  local steps = math.floor(over / 5) + 1
                  local pen = math.min(steps * ATC_AI.academy.bankRules.penaltyPer5deg, ATC_AI.academy.bankRules.maxPenalty)
                  s.score = math.max(0, s.score - pen)
                  s.bankPenalizedThisRecovery = true
                  _addNote(s, string.format("Bank >%d° at 90 (-%d)", maxB, pen))
                  msgToUnit(u, string.format("[ACADEMY] Penalty: BANK %.0f° at 90 (-%d)", bank, pen), 7)
                end
              end

              -- Flat pattern checkpoint ONLY at 90 (once per recovery)
              if s.recoveryArmed and (not s.flatPenalizedThisRecovery) then
                local max90 = ATC_AI.academy.flatPatternRules.at90_maxAGL_ft
                if agl_ft > max90 then
                  local diff = agl_ft - max90
                  local steps = math.floor(diff / 100) + 1
                  local pen = math.min(steps * ATC_AI.academy.flatPatternRules.penaltyPer100ft,
                                       ATC_AI.academy.flatPatternRules.maxPenalty)
                  s.score = math.max(0, s.score - pen)
                  s.flatPenalizedThisRecovery = true
                  _addNote(s, string.format("Flat pattern @90 (%.0fft, -%d)", agl_ft, pen))
                  msgToUnit(u, string.format("[ACADEMY] Penalty: FLAT @90 (%.0fft, -%d)", agl_ft, pen), 7)
                end
              end
            end
          end

          -- Overshoot centerline penalty in final phase (once per recovery)
          if s.recoveryArmed and s.at90 and (not s.overshootPenalizedThisRecovery) then
            local os = ATC_AI.academy.finalPenalties.overshootM
            local osBig = ATC_AI.academy.finalPenalties.overshootBigM
            if latAbsM > os then
              local pen = ATC_AI.academy.finalPenalties.overshootPenalty
              if latAbsM > osBig then pen = ATC_AI.academy.finalPenalties.overshootBigPenalty end
              s.score = math.max(0, s.score - pen)
              s.overshootPenalizedThisRecovery = true
              _addNote(s, string.format("Final overshoot %.0fm (-%d)", latAbsM, pen))
              msgToUnit(u, string.format("[ACADEMY] Penalty: FINAL OVERSHOOT %.0fm (-%d)", latAbsM, pen), 7)
            end
          end

          -- FINAL stable (geometric)
          local alignedF = (_degDiff(trk, rwyHdg) <= ATC_AI.academy.final.hdg_tol)
          local centered = (latAbsM <= ATC_AI.academy.final.centerlineMaxM)

          if s.at90 and alignedF and centered and (agl_ft <= ATC_AI.academy.final.agl_max) then
            s.finalStableSeconds = s.finalStableSeconds + 1
            if (not s.finalStable) and s.finalStableSeconds >= ATC_AI.academy.final.minSecondsStable then
              s.finalStable = true
              s.score = s.score + ATC_AI.academy.weights.final
              _throttledFeedback(u, name, "Final stable", 2)
            end
          else
            if not s.finalStable then
              s.finalStableSeconds = 0
            end
          end
        end
      end
    end
  end

  return timer.getTime() + 1
end

timer.scheduleFunction(function() return _academyMonitor() end, {}, timer.getTime() + 5)
trigger.action.outText("[ATC_AI][ACADEMY] Enabled: Overhead-only A+B grading (1500 AGL / 300 kt initial).", 12)
env.info("[ATC_AI][ACADEMY] Academy module loaded.")