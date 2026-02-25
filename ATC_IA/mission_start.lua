-- =========================
-- ATC_AI PoC - Kutaisi (Caucasus)
-- Autonomous Military ATC + Recovery Manager (MVP, MP-safe callbacks)
-- No external libs required (NO MOOSE/MIST).
--
-- Key design choice:
--  * missionCommands callbacks do NOT use Group.getById()
--  * We bind each F10 menu to a specific leader unitName at creation time.
--
-- Features:
--  - F10 menu per player group (Request Taxi/Takeoff/RTB/Emergency/Status/Cancel)
--  - Dynamic runway (07/25) based on surface wind at airbase
--  - Runway occupancy/separation timer + resequencing
--  - Priority model: Emergency > Fuel low > Others
--  - Basic metrics log to dcs.log
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

    patternAGL_ft = 2000,    -- suggested pattern altitude AGL
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
    -- fallback to global if unit is gone
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
  -- Determine runway based on surface wind direction at airbase.
  -- Wind vector from atmosphere.getWind() is "to" direction; we convert to "from".
  local p, elev = getAirbasePointAndElev()
  if not p then return ATC_AI.state.activeRWY or "07" end

  local w = atmosphere.getWind({x=p.x, y=elev + 10, z=p.z})
  local wx, wz = w.x or 0, w.z or 0

  -- calm -> keep previous
  if math.abs(wx) < 0.5 and math.abs(wz) < 0.5 then
    return ATC_AI.state.activeRWY or "07"
  end

  local toRad = math.atan2(wx, wz) -- x east, z north
  local toDeg = (math.deg(toRad) + 360) % 360
  local fromDeg = (toDeg + 180) % 360

  local function angDiff(a,b)
    local d = math.abs(a-b) % 360
    return (d > 180) and (360-d) or d
  end

  local d07 = angDiff(fromDeg, 70)   -- RWY 07 ~ 070
  local d25 = angDiff(fromDeg, 250)  -- RWY 25 ~ 250

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

  -- damage heuristic
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
  -- update runway by wind
  ATC_AI.state.activeRWY = computeActiveRunway07_25()

  -- refresh priorities based on current unit state
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

  -- Decision:
  -- - If inbound prio >= 4 -> inbound first
  -- - else prefer outbound when runway free, else keep inbound updated
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
  -- Create menus for any BLUE player units found
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

  -- Ensure menu exists for player group (if applicable)
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