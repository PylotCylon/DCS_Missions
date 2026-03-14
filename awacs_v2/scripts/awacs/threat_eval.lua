local util = require("awacs.util")

local M = {}

local function compute_score(distance_nm, aspect, contact_alt_ft, pkg_alt_ft, cfg)
    local threat_cfg = cfg.threat or {}
    if distance_nm > (threat_cfg.max_range_nm or 80) then return nil end
    if distance_nm < (threat_cfg.min_range_nm or 0) then return nil end

    local max_range = threat_cfg.max_range_nm or 80
    local range_component = util.clamp((max_range - distance_nm) / max_range, 0, 1) * 60

    local aspect_bonus = 0
    if aspect == "hot" then
        aspect_bonus = threat_cfg.hot_bonus or 0
    elseif aspect == "flank" then
        aspect_bonus = threat_cfg.flank_bonus or 0
    end

    local alt_delta = math.abs((contact_alt_ft or 0) - (pkg_alt_ft or 0))
    local alt_component = util.clamp(1 - (alt_delta / 20000), 0, 1) * 10

    local score = range_component + aspect_bonus + alt_component
    return score
end

function M.evaluate(tracks, packages, config, now)
    local results = {}
    if not packages or #packages == 0 then
        return results
    end

    for _, pkg in ipairs(packages) do
        for _, track in pairs(tracks or {}) do
            local distance = util.distance_nm(pkg.position, track.position)
            local bearing = util.bearing_deg(pkg.position, track.position)
            local aspect = util.aspect_tag(track.heading_deg, bearing)
            local score = compute_score(distance, aspect, track.altitude_ft, pkg.altitude_ft, config)

            if score and score >= ((config.threat and config.threat.min_score) or 0) then
                table.insert(results, {
                    track = track,
                    package = pkg,
                    distance_nm = distance,
                    bearing_deg = bearing,
                    aspect = aspect,
                    score = score,
                    last_seen = track.last_seen,
                    time = now,
                })
            end
        end
    end

    table.sort(results, function(a, b)
        if a.score == b.score then
            return a.distance_nm < b.distance_nm
        end
        return a.score > b.score
    end)

    return results
end

return M
