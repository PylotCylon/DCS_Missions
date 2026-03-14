local util = require("awacs.util")

local M = {}

local function normalize_package(pkg)
    if not pkg then return nil end
    return {
        id = pkg.id or pkg.name,
        name = pkg.name,
        callsign = pkg.callsign or pkg.name,
        coalition = pkg.coalition or "blue",
        position = pkg.position or pkg.pos or { x = 0, z = 0 },
        altitude_ft = pkg.altitude_ft or pkg.alt_ft or util.ft_from_meters(pkg.altitude_m or 0),
        heading_deg = pkg.heading_deg or pkg.heading or 0,
        speed_kts = pkg.speed_kts or pkg.speed or 0,
    }
end

local function normalize_contact(c)
    if not c then return nil end
    return {
        id = c.id or c.name,
        name = c.name,
        coalition = c.coalition or "red",
        position = c.position or c.pos or { x = 0, z = 0 },
        altitude_ft = c.altitude_ft or c.alt_ft or util.ft_from_meters(c.altitude_m or 0),
        heading_deg = c.heading_deg or c.heading or 0,
        speed_kts = c.speed_kts or c.speed or 0,
        category = c.category,
        last_seen = c.last_seen,
    }
end

local function safe_call(fn)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

function M.build_snapshot(world_state, adapters, config, now)
    adapters = adapters or {}
    config = config or {}
    world_state = world_state or safe_call(adapters.read_world) or {}

    local snapshot = {
        packages = {},
        hostiles = {},
        bullseye = world_state.bullseye or config.bullseye,
        time = now,
    }

    for _, pkg in ipairs(world_state.packages or {}) do
        local normalized = normalize_package(pkg)
        if normalized then
            table.insert(snapshot.packages, normalized)
        end
    end

    for _, contact in ipairs(world_state.hostiles or {}) do
        local normalized = normalize_contact(contact)
        if normalized then
            table.insert(snapshot.hostiles, normalized)
        end
    end

    return snapshot
end

return M
