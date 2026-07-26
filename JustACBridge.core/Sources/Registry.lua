-- Pluggable recommendation-source registry.
--
-- A custom source only needs GetQueue() when JustAC is installed: the bridge
-- can fall back to the JustAC source for hotkeys and runtime spell queries.
-- A standalone source may implement the optional capability methods documented
-- in Sources/README.md.

local Registry = _G.JustACBridgeRecommendationSources or {}
_G.JustACBridgeRecommendationSources = Registry

Registry.schemaVersion = 1
Registry.sources = Registry.sources or {}
Registry.order = Registry.order or {}

local function initialize(source)
    if source._bridgeInitialized then
        return source._bridgeAvailable, source._bridgeError
    end

    source._bridgeInitialized = true
    local available, reason = true, nil
    if type(source.Initialize) == "function" then
        local ok, result, detail = pcall(source.Initialize)
        if not ok then
            available, reason = false, tostring(result)
        elseif result == false then
            available, reason = false, detail or "initialization failed"
        end
    end
    if available and type(source.IsAvailable) == "function" then
        local ok, result, detail = pcall(source.IsAvailable)
        if not ok then
            available, reason = false, tostring(result)
        elseif result == false then
            available, reason = false, detail or "unavailable"
        end
    end

    source._bridgeAvailable = available
    source._bridgeError = reason
    return available, reason
end

function Registry.Register(id, source)
    if type(id) ~= "string" or id == "" or type(source) ~= "table"
        or type(source.GetQueue) ~= "function" then
        return false
    end
    if not Registry.sources[id] then
        Registry.order[#Registry.order + 1] = id
    end
    source.id = id
    source.name = source.name or id
    Registry.sources[id] = source
    return true
end

function Registry.Get(id, requireAvailable)
    local source = Registry.sources[id]
    if not source then
        return nil, "unknown source"
    end
    if requireAvailable ~= false then
        local available, reason = initialize(source)
        if not available then
            return nil, reason
        end
    end
    return source
end

function Registry.Select(preferredID)
    if preferredID then
        local preferred = Registry.Get(preferredID)
        if preferred then
            return preferred
        end
    end
    for _, id in ipairs(Registry.order) do
        local source = Registry.Get(id)
        if source then
            return source
        end
    end
    return nil, "no recommendation source is available"
end

function Registry.List()
    local result = {}
    for _, id in ipairs(Registry.order) do
        local source = Registry.sources[id]
        local available, reason = initialize(source)
        result[#result + 1] = {
            id = id,
            name = source.name,
            available = available,
            reason = reason,
        }
    end
    return result
end

