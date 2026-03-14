local util = require("awacs.util")

local M = {}

function M.update(state, snapshot, config, now)
    state.tracks = state.tracks or {}
    local tracks = state.tracks
    local loss_limit = (config.tracking and config.tracking.track_loss_sec) or 90

    for _, track in pairs(tracks) do
        track._stale = true
    end

    for _, contact in ipairs(snapshot.hostiles or {}) do
        local id = contact.id or contact.name
        if id then
            local t = tracks[id] or { id = id, name = contact.name, first_seen = now }
            t.last_seen = now
            t.position = contact.position
            t.altitude_ft = contact.altitude_ft
            t.heading_deg = contact.heading_deg
            t.speed_kts = contact.speed_kts
            t.category = contact.category
            t._stale = false
            tracks[id] = t
        end
    end

    for id, t in pairs(tracks) do
        local time_since_seen = now - (t.last_seen or 0)
        if time_since_seen > loss_limit then
            tracks[id] = nil
        end
    end

    return tracks
end

return M
