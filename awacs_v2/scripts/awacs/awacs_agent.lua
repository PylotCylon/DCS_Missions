local Config = require("awacs.awacs_config")
local perception = require("awacs.perception")
local tracking = require("awacs.tracking")
local threat_eval = require("awacs.threat_eval")
local comms = require("awacs.comms")
local message_builder = require("awacs.message_builder")
local output = require("awacs.output")
local util = require("awacs.util")

local AwacsAgent = {}
AwacsAgent.__index = AwacsAgent

function AwacsAgent.new(opts)
    opts = opts or {}
    local self = setmetatable({}, AwacsAgent)
    self.config = Config.merge(opts.config or {})
    self.adapters = opts.adapters or {}
    self.tracking_state = { tracks = {} }
    self.comms_state = {
        package_last_call = {},
        track_last_call = {},
        last_global_call = 0,
    }
    return self
end

function AwacsAgent:reset()
    self.tracking_state = { tracks = {} }
    self.comms_state = {
        package_last_call = {},
        track_last_call = {},
        last_global_call = 0,
    }
end

function AwacsAgent:tick(world_state, now)
    now = now or util.safe_now(self.adapters)
    local snapshot = perception.build_snapshot(world_state, self.adapters, self.config, now)

    tracking.update(self.tracking_state, snapshot, self.config, now)

    local threats = threat_eval.evaluate(self.tracking_state.tracks, snapshot.packages, self.config, now)
    local calls = comms.select_calls(threats, self.comms_state, self.config, now)

    local messages = {}
    for _, call in ipairs(calls) do
        if call.type == "braa" then
            table.insert(messages, message_builder.build_braa(call, self.config))
        end
    end

    output.send(messages, self.adapters, self.config, now)

    if self.config.debug.trace then
        output.log_state(self.adapters, self.config, {
            snapshot = snapshot,
            threats = threats,
            calls = calls,
            time = now,
        }, now)
    end

    return messages
end

return AwacsAgent
