local util = require("awacs.util")

local M = {}

local KTS_PER_MPS = 1.943844

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    return pcall(fn, ...)
end

local function default_log(prefix, text)
    local line = string.format("%s %s", prefix, text)
    if env and env.info then
        env.info(line)
    else
        print(line)
    end
end

local function vector_speed_kts(v)
    if not v then return 0 end
    local vx = v.x or 0
    local vy = v.y or 0
    local vz = v.z or 0
    local speed_mps = math.sqrt(vx * vx + vy * vy + vz * vz)
    return speed_mps * KTS_PER_MPS
end

local function vector_heading_deg(v)
    if not v then return 0 end
    local vx = v.x or 0
    local vz = v.z or 0
    if vx == 0 and vz == 0 then
        return 0
    end

    local heading = math.deg(math.atan2(vx, vz))
    if heading < 0 then
        heading = heading + 360
    end
    return heading
end

local function first_dcs_unit_from_group(group)
    if not group then return nil end

    if group.GetDCSObject then
        local ok_obj, dcs_group = safe_call(group.GetDCSObject, group)
        if ok_obj and dcs_group and dcs_group.isExist and dcs_group:isExist() then
            local unit = dcs_group:getUnit(1)
            if unit and unit.isExist and unit:isExist() then
                return unit
            end
        end
    end

    if group.getUnit and group.isExist and group:isExist() then
        local unit = group:getUnit(1)
        if unit and unit.isExist and unit:isExist() then
            return unit
        end
    end

    return nil
end

local function group_name(group)
    if not group then return nil end

    if group.GetName then
        local ok_name, name = safe_call(group.GetName, group)
        if ok_name and name then
            return name
        end
    end

    if group.getName then
        local ok_name, name = safe_call(group.getName, group)
        if ok_name and name then
            return name
        end
    end

    return nil
end

local function find_group_by_name(name)
    if GROUP and GROUP.FindByName then
        local ok_group, moose_group = safe_call(GROUP.FindByName, GROUP, name)
        if ok_group and moose_group then
            return moose_group
        end
    end

    if Group and Group.getByName then
        return Group.getByName(name)
    end

    return nil
end

local function group_to_contact(group, coalition_label)
    local unit = first_dcs_unit_from_group(group)
    if not unit then
        return nil
    end

    local point = unit:getPoint()
    local velocity = unit:getVelocity()
    if not point then
        return nil
    end

    local name = group_name(group) or "UNKNOWN"
    return {
        id = name,
        name = name,
        coalition = coalition_label,
        position = { x = point.x or 0, z = point.z or 0 },
        altitude_ft = util.ft_from_meters(point.y or 0),
        heading_deg = vector_heading_deg(velocity),
        speed_kts = vector_speed_kts(velocity),
        category = "air",
    }
end

local function list_from_named_groups(group_names, coalition_label)
    local contacts = {}
    for _, name in ipairs(group_names or {}) do
        local group = find_group_by_name(name)
        local contact = group_to_contact(group, coalition_label)
        if contact then
            table.insert(contacts, contact)
        end
    end
    return contacts
end

local function build_filtered_set(prefixes, coalition_label)
    if not (SET_GROUP and SET_GROUP.New) then
        return nil
    end

    local set = SET_GROUP:New()
    if prefixes and #prefixes > 0 and set.FilterPrefixes then
        set:FilterPrefixes(prefixes)
    end
    if set.FilterCoalitions then
        set:FilterCoalitions(coalition_label)
    end
    if set.FilterCategoryAirplane then
        set:FilterCategoryAirplane()
    end
    if set.FilterStart then
        set:FilterStart()
    end
    return set
end

local function list_from_group_set(group_set, coalition_label)
    local contacts = {}
    if not group_set or not group_set.ForEachGroup then
        return contacts
    end

    group_set:ForEachGroup(function(group)
        local contact = group_to_contact(group, coalition_label)
        if contact then
            table.insert(contacts, contact)
        end
    end)

    return contacts
end

local function coalition_side_from_label(label)
    if not (coalition and coalition.side) then
        return nil
    end
    if label == "red" then return coalition.side.RED end
    if label == "blue" then return coalition.side.BLUE end
    return coalition.side.NEUTRAL
end

function M.new(opts)
    opts = opts or {}

    local prefix = opts.log_prefix or "[AWACS:MOOSE]"
    local adapter = {
        package_group_names = opts.package_group_names or {},
        hostile_group_names = opts.hostile_group_names or {},
        output_coalition = opts.output_coalition or "blue",
        message_duration_sec = opts.message_duration_sec or 10,
        message_category = opts.message_category or "AWACS",
        package_set = build_filtered_set(opts.package_group_prefixes, "blue"),
        hostile_set = build_filtered_set(opts.hostile_group_prefixes, "red"),
    }

    adapter.log = function(text)
        default_log(prefix, text)
    end

    adapter.now = function()
        if timer and timer.getTime then
            return timer.getTime()
        end
        return os.clock()
    end

    adapter.read_world = function()
        local packages = list_from_named_groups(adapter.package_group_names, "blue")
        local hostiles = list_from_named_groups(adapter.hostile_group_names, "red")

        -- Prefix-based sets are optional; they let us avoid hardcoding every group name.
        local by_set_packages = list_from_group_set(adapter.package_set, "blue")
        local by_set_hostiles = list_from_group_set(adapter.hostile_set, "red")

        local dedupe = {}
        for _, c in ipairs(packages) do
            dedupe[c.id] = c
        end
        for _, c in ipairs(by_set_packages) do
            dedupe[c.id] = c
        end

        local merged_packages = {}
        for _, c in pairs(dedupe) do
            table.insert(merged_packages, c)
        end

        dedupe = {}
        for _, c in ipairs(hostiles) do
            dedupe[c.id] = c
        end
        for _, c in ipairs(by_set_hostiles) do
            dedupe[c.id] = c
        end

        local merged_hostiles = {}
        for _, c in pairs(dedupe) do
            table.insert(merged_hostiles, c)
        end

        return {
            packages = merged_packages,
            hostiles = merged_hostiles,
        }
    end

    adapter.send_text = function(text)
        local output_side = coalition_side_from_label(adapter.output_coalition)

        if MESSAGE and MESSAGE.New then
            local msg = MESSAGE:New(text, adapter.message_duration_sec, adapter.message_category)
            if output_side and msg.ToCoalition then
                msg:ToCoalition(output_side)
                return
            end
            if msg.ToAll then
                msg:ToAll()
                return
            end
        end

        if trigger and trigger.action then
            if output_side and trigger.action.outTextForCoalition then
                trigger.action.outTextForCoalition(output_side, text, adapter.message_duration_sec)
                return
            end
            if trigger.action.outText then
                trigger.action.outText(text, adapter.message_duration_sec)
                return
            end
        end

        adapter.log(text)
    end

    return adapter
end

function M.start(agent, opts)
    opts = opts or {}
    local interval_sec = opts.interval_sec or 10
    local start_delay_sec = opts.start_delay_sec or 3

    if not (timer and timer.scheduleFunction and timer.getTime) then
        return nil, "timer API not available"
    end

    local function step(_, now)
        agent:tick(nil, now)
        return now + interval_sec
    end

    local first_tick = timer.getTime() + start_delay_sec
    local id = timer.scheduleFunction(step, nil, first_tick)

    return {
        id = id,
        stop = function()
            if timer and timer.removeFunction and id then
                timer.removeFunction(id)
            end
        end
    }
end

return M
