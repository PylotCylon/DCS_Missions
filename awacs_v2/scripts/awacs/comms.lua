local M = {}

local function angle_delta_deg(a, b)
    local diff = math.abs(((a - b + 540) % 360) - 180)
    return diff
end

local function is_significant_change(previous, threat, cfg)
    if not previous then
        return true
    end

    local bearing_delta = angle_delta_deg(threat.bearing_deg or 0, previous.bearing_deg or 0)
    if bearing_delta >= (cfg.min_bearing_delta_deg or 12) then
        return true
    end

    local range_delta = math.abs((threat.distance_nm or 0) - (previous.distance_nm or 0))
    if range_delta >= (cfg.min_range_delta_nm or 6) then
        return true
    end

    local altitude_delta = math.abs((threat.track.altitude_ft or 0) - (previous.altitude_ft or 0))
    if altitude_delta >= (cfg.min_altitude_delta_ft or 2000) then
        return true
    end

    if (cfg.reannounce_on_aspect_change ~= false) and (threat.aspect ~= previous.aspect) then
        return true
    end

    return false
end

local function message_key(pkg_id, track_id)
    return string.format("%s|%s", tostring(pkg_id or "nil"), tostring(track_id or "nil"))
end

function M.select_calls(threats, state, config, now)
    state.package_last_call = state.package_last_call or {}
    state.track_last_call = state.track_last_call or {}
    state.last_global_call = state.last_global_call or 0
    state.last_announced = state.last_announced or {}

    local cfg_comms = config.comms or {}
    local max_calls = cfg_comms.max_calls_per_tick or 1
    local pkg_cd = cfg_comms.package_cooldown_sec or 30
    local global_cd = cfg_comms.global_cooldown_sec or 8
    local track_cd = cfg_comms.track_repeat_sec or 30
    local duplicate_window = cfg_comms.duplicate_suppression_sec
        or ((config.evaluation and config.evaluation.duplicate_suppression_sec) or 20)

    local calls = {}

    for _, threat in ipairs(threats or {}) do
        if #calls >= max_calls then
            break
        end

        local pkg_id = threat.package.id or threat.package.name
        local track_id = threat.track.id or threat.track.name

        if pkg_id and track_id then
            local pkg_ready = (now - (state.package_last_call[pkg_id] or -math.huge)) >= pkg_cd
            local global_ready = (now - (state.last_global_call or 0)) >= global_cd
            local track_ready = (now - (state.track_last_call[track_id] or -math.huge)) >= track_cd
            local key = message_key(pkg_id, track_id)
            local previous = state.last_announced[key]
            local duplicate_age = previous and (now - (previous.time or 0)) or math.huge
            local significant = is_significant_change(previous, threat, cfg_comms)
            local duplicate_ready = duplicate_age >= duplicate_window or significant

            if pkg_ready and global_ready and track_ready and duplicate_ready then
                table.insert(calls, {
                    type = "braa",
                    threat = threat,
                })
                state.package_last_call[pkg_id] = now
                state.track_last_call[track_id] = now
                state.last_global_call = now
                state.last_announced[key] = {
                    time = now,
                    bearing_deg = threat.bearing_deg,
                    distance_nm = threat.distance_nm,
                    altitude_ft = threat.track.altitude_ft,
                    aspect = threat.aspect,
                }
            end
        end
    end

    return calls
end

return M
