-- Example mission bootstrap (DO SCRIPT FILE after MOOSE and AWACS modules are loaded)
local MooseBootstrap = require("awacs.bootstrap_moose")

local instance, err = MooseBootstrap.start({
    config = {
        profile = "tactical_realistic",
        evaluation = { interval_sec = 10 },
        comms = {
            package_cooldown_sec = 35,
            global_cooldown_sec = 8,
            max_calls_per_tick = 1,
        },
        outputs = {
            prefix = "[MAGIC]",
        },
    },
    adapter = {
        package_group_names = { "COLT11", "PONTIAC21" },
        hostile_group_prefixes = { "RED_CAP_", "RED_INTERCEPT_" },
        output_coalition = "blue",
        message_duration_sec = 8,
    },
    runtime = {
        interval_sec = 10,
        start_delay_sec = 5,
    }
})

if not instance then
    if env and env.error then
        env.error(string.format("AWACS bootstrap failed: %s", err or "unknown"))
    else
        print(string.format("AWACS bootstrap failed: %s", err or "unknown"))
    end
end
