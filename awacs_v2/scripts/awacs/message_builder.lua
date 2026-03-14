local M = {}

local function fmt_bearing(deg)
    return string.format("%03d", math.floor((deg or 0) + 0.5))
end

local function fmt_distance(nm)
    return string.format("%d", math.floor((nm or 0) + 0.5))
end

local function fmt_angels(ft)
    local kft = math.max(0, math.floor(((ft or 0) / 1000) + 0.5))
    return "angels " .. kft
end

function M.build_braa(call, config)
    local threat = call.threat
    local pkg = threat.package
    local track = threat.track

    local text = string.format(
        "%s, BRAA %s for %s, %s, %s",
        pkg.callsign or pkg.name or "PACKAGE",
        fmt_bearing(threat.bearing_deg),
        fmt_distance(threat.distance_nm),
        fmt_angels(track.altitude_ft),
        threat.aspect or "aspect"
    )

    local prefix = config.outputs and config.outputs.prefix
    if prefix and prefix ~= "" then
        text = prefix .. " " .. text
    end

    return {
        type = "braa",
        text = text,
        package = pkg,
        track = track,
        meta = {
            distance_nm = threat.distance_nm,
            bearing_deg = threat.bearing_deg,
            aspect = threat.aspect,
            score = threat.score,
        }
    }
end

return M

