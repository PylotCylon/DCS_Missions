-- Academy profile bootstrap (DO SCRIPT FILE after MOOSE and AWACS modules are loaded)
local MooseBootstrap = require("awacs.bootstrap_moose")

local instance, err = MooseBootstrap.start({
    profile = "academy_basic",
    config = {
        -- Optional mission-specific override on top of academy_basic preset.
        comms = {
            max_calls_per_tick = 2,
        },
    },
    adapter = {
        package_group_prefixes = { "BLUE_ACA_" },
        hostile_group_prefixes = { "RED_ACA_" },
        output_coalition = "blue",
        message_duration_sec = 8,
    },
    runtime = {
        interval_sec = 8,
        start_delay_sec = 5,
    }
})

if not instance then
    if env and env.error then
        env.error(string.format("AWACS academy bootstrap failed: %s", err or "unknown"))
    else
        print(string.format("AWACS academy bootstrap failed: %s", err or "unknown"))
    end
end
