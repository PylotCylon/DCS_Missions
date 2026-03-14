local AwacsAgent = require("awacs.awacs_agent")
local AwacsConfig = require("awacs.awacs_config")
local MooseAdapter = require("awacs.adapters.moose_adapter")
local ProfilePresets = require("awacs.profile_presets")

local M = {}

function M.start(opts)
    opts = opts or {}

    local profile_name = opts.profile or (opts.config and opts.config.profile) or "tactical_realistic"
    local preset_config = ProfilePresets.get(profile_name)
    local final_config = AwacsConfig.merge_many({ preset_config, opts.config or {} })

    local adapter = MooseAdapter.new(opts.adapter or {})
    local agent = AwacsAgent.new({
        config = final_config,
        adapters = adapter,
    })

    local runner, err = MooseAdapter.start(agent, opts.runtime or {})
    if not runner then
        adapter.log(string.format("Startup failed: %s", err or "unknown error"))
        return nil, err
    end

    adapter.log(string.format("AWACS started with MOOSE adapter (profile=%s)", profile_name))

    return {
        agent = agent,
        adapter = adapter,
        runner = runner,
        profile = profile_name,
    }
end

return M
