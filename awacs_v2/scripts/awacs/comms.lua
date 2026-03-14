local M = {}

function M.select_calls(threats, state, config, now)
    state.package_last_call = state.package_last_call or {}
    state.track_last_call = state.track_last_call or {}
    state.last_global_call = state.last_global_call or 0

    local cfg_comms = config.comms or {}
    local max_calls = cfg_comms.max_calls_per_tick or 1
    local pkg_cd = cfg_comms.package_cooldown_sec or 30
    local global_cd = cfg_comms.global_cooldown_sec or 8
    local track_cd = cfg_comms.track_repeat_sec or 30

    local calls = {}

    for _, threat in ipairs(threats or {}) do
        if #calls >= max_calls then
            break
        end

        local pkg_id = threat.package.id or threat.package.name
        local track_id = threat.track.id

        local pkg_ready = (now - (state.package_last_call[pkg_id] or -math.huge)) >= pkg_cd
        local global_ready = (now - (state.last_global_call or 0)) >= global_cd
        local track_ready = (now - (state.track_last_call[track_id] or -math.huge)) >= track_cd

        if pkg_ready and global_ready and track_ready then
            table.insert(calls, {
                type = "braa",
                threat = threat,
            })
            state.package_last_call[pkg_id] = now
            state.track_last_call[track_id] = now
            state.last_global_call = now
        end
    end

    return calls
end

return M
