local M = {}

M.defaults = {
    profile = "tactical_realistic",
    evaluation = {
        interval_sec = 10,
        duplicate_suppression_sec = 20,
    },
    tracking = {
        track_loss_sec = 90,
    },
    threat = {
        max_range_nm = 80,
        min_range_nm = 5,
        min_score = 0.2,
        closing_bonus = 25,
        hot_bonus = 20,
        flank_bonus = 10,
    },
    comms = {
        package_cooldown_sec = 40,
        global_cooldown_sec = 8,
        track_repeat_sec = 30,
        max_calls_per_tick = 2,
        duplicate_suppression_sec = 20,
        min_bearing_delta_deg = 12,
        min_range_delta_nm = 6,
        min_altitude_delta_ft = 2000,
        reannounce_on_aspect_change = true,
    },
    outputs = {
        text = true,
        log = true,
        prefix = "[AWACS]",
    },
    debug = {
        enabled = false,
        trace = false,
    }
}

local function deep_copy(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            result[k] = deep_copy(v)
        else
            result[k] = v
        end
    end
    return result
end

local function deep_merge(base, override)
    local merged = deep_copy(base)
    for k, v in pairs(override or {}) do
        if type(v) == "table" and type(merged[k]) == "table" then
            merged[k] = deep_merge(merged[k], v)
        else
            merged[k] = v
        end
    end
    return merged
end

function M.merge(user_config)
    return deep_merge(M.defaults, user_config or {})
end

function M.merge_many(configs)
    local merged = deep_copy(M.defaults)
    for _, cfg in ipairs(configs or {}) do
        merged = deep_merge(merged, cfg or {})
    end
    return merged
end

return M
