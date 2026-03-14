local M = {}

local function default_log(text)
    print(text)
end

function M.send(messages, adapters, _config, _now)
    adapters = adapters or {}
    local log_fn = adapters.log or default_log

    for _, msg in ipairs(messages or {}) do
        if adapters.send_text then
            adapters.send_text(msg.text, msg)
        else
            log_fn(msg.text)
        end
    end
end

function M.log_state(adapters, config, state, now)
    if not (config.debug and config.debug.enabled) then
        return
    end
    adapters = adapters or {}
    local log_fn = adapters.log or default_log

    local threats = state.threats and #state.threats or 0
    local calls = state.calls and #state.calls or 0
    local prefix = (config.outputs and config.outputs.prefix) or "[AWACS]"
    log_fn(string.format("%s TRACE t=%.1f threats=%d calls=%d", prefix, now or 0, threats, calls))
end

return M
