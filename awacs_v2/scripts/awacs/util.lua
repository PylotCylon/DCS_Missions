local util = {}

local NM_IN_METERS = 1852
local FT_IN_METERS = 0.3048

local function clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

function util.nm_from_meters(m)
    return m / NM_IN_METERS
end

function util.meters_from_nm(nm)
    return nm * NM_IN_METERS
end

function util.ft_from_meters(m)
    return m / FT_IN_METERS
end

function util.meters_from_ft(ft)
    return ft * FT_IN_METERS
end

function util.distance_nm(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dz = (a.z or 0) - (b.z or 0)
    local dist_m = math.sqrt(dx * dx + dz * dz)
    return util.nm_from_meters(dist_m)
end

function util.bearing_deg(from, to)
    if not from or not to then return 0 end
    local dx = (to.x or 0) - (from.x or 0)
    local dz = (to.z or 0) - (from.z or 0)
    if dx == 0 and dz == 0 then
        return 0
    end
    local bearing = math.deg(math.atan2(dx, dz))
    if bearing < 0 then
        bearing = bearing + 360
    end
    return bearing
end

function util.aspect_tag(track_heading_deg, bearing_to_package_deg)
    if not track_heading_deg or not bearing_to_package_deg then
        return "unknown"
    end
    local diff = ((track_heading_deg - bearing_to_package_deg + 540) % 360) - 180
    local adiff = math.abs(diff)
    if adiff <= 45 then
        return "hot"
    elseif adiff <= 135 then
        return "flank"
    else
        return "cold"
    end
end

function util.round(num, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor(num * power + 0.5) / power
end

function util.safe_now(adapters)
    if adapters and adapters.now then
        local ok, value = pcall(adapters.now)
        if ok and value then
            return value
        end
    end
    return os.clock()
end

util.clamp = clamp

return util
