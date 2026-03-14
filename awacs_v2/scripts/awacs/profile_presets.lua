local M = {}

M.profiles = {
    tactical_realistic = {
        profile = "tactical_realistic",
        evaluation = {
            interval_sec = 10,
            duplicate_suppression_sec = 20,
        },
        comms = {
            package_cooldown_sec = 40,
            global_cooldown_sec = 8,
            track_repeat_sec = 30,
            max_calls_per_tick = 2,
        },
        outputs = {
            prefix = "[AWACS]",
        },
        debug = {
            enabled = false,
            trace = false,
        }
    },

    academy_basic = {
        profile = "academy_basic",
        evaluation = {
            interval_sec = 8,
            duplicate_suppression_sec = 12,
        },
        threat = {
            max_range_nm = 100,
            min_range_nm = 3,
            min_score = 0.1,
            hot_bonus = 15,
            flank_bonus = 8,
        },
        comms = {
            package_cooldown_sec = 20,
            global_cooldown_sec = 4,
            track_repeat_sec = 12,
            max_calls_per_tick = 3,
        },
        outputs = {
            prefix = "[AWACS ACADEMY]",
        },
        debug = {
            enabled = true,
            trace = false,
        }
    }
}

function M.get(name)
    if not name then
        return M.profiles.tactical_realistic
    end
    return M.profiles[name] or M.profiles.tactical_realistic
end

return M
