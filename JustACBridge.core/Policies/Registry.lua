-- Central class-policy registry.
--
-- Class files register stable per-specialization defaults.  Optional version
-- patches let a future game update add/remove/replace spell IDs without
-- touching JustACBridge.lua or invalidating the player's saved overrides.

local Registry = _G.JustACBridgePolicyRegistry or {}
_G.JustACBridgePolicyRegistry = Registry

Registry.schemaVersion = 4
Registry.classes = Registry.classes or {}

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function replaceArray(target, source)
    for index = #target, 1, -1 do
        target[index] = nil
    end
    for index, value in ipairs(source or {}) do
        target[index] = value
    end
end

local function copyRangeSequenceRules(source)
    local result = {}
    for index, rule in ipairs(source or {}) do
        if type(rule) == "table" then
            result[index] = {
                requiresSpell = tonumber(rule.requiresSpell),
                beyond = tonumber(rule.beyond),
                defer = copyArray(rule.defer),
                prefer = copyArray(rule.prefer),
            }
        end
    end
    return result
end

local function appendRangeSequenceRules(target, source)
    for _, rule in ipairs(copyRangeSequenceRules(source)) do
        target[#target + 1] = rule
    end
end

local function copyGroundEffects(source)
    local result = {}
    for _, rule in ipairs(source or {}) do
        if type(rule) == "table" then
            result[#result + 1] = {
                id = rule.id,
                name = rule.name,
                spells = copyArray(rule.spells),
                duration = tonumber(rule.duration),
                suppressRepeat = rule.suppressRepeat ~= false,
            }
        end
    end
    return result
end

local function appendGroundEffects(target, source)
    for _, rule in ipairs(copyGroundEffects(source)) do
        target[#target + 1] = rule
    end
end

local function removeValues(target, values)
    local removed = {}
    for _, value in ipairs(values or {}) do
        local spellID = tonumber(value)
        if spellID then
            removed[spellID] = true
        end
    end

    local writeIndex = 1
    for readIndex = 1, #target do
        local value = target[readIndex]
        if not removed[value] then
            target[writeIndex] = value
            writeIndex = writeIndex + 1
        end
    end
    for index = #target, writeIndex, -1 do
        target[index] = nil
    end
end

local function addUniqueValues(target, values)
    local present = {}
    for _, value in ipairs(target) do
        present[value] = true
    end
    for _, value in ipairs(values or {}) do
        value = tonumber(value)
        if value and value > 0 and not present[value] then
            target[#target + 1] = value
            present[value] = true
        end
    end
end

local function getInterfaceVersion()
    if not GetBuildInfo then
        return 0
    end
    local _, _, _, interfaceVersion = GetBuildInfo()
    return tonumber(interfaceVersion) or 0
end

local function selectVersionPatch(specPolicy, interfaceVersion)
    local selected
    local selectedMinimum = -1
    for _, patch in ipairs(specPolicy.versions or {}) do
        local minimum = tonumber(patch.minInterface) or 0
        local maximum = tonumber(patch.maxInterface) or math.huge
        if interfaceVersion >= minimum and interfaceVersion <= maximum
            and minimum >= selectedMinimum then
            selected = patch
            selectedMinimum = minimum
        end
    end
    return selected
end

function Registry.RegisterClass(classFile, definition)
    if type(classFile) ~= "string" or classFile == ""
        or type(definition) ~= "table" or type(definition.specs) ~= "table" then
        return false
    end

    definition.classFile = classFile
    Registry.classes[classFile] = definition
    return true
end

function Registry.Resolve(classFile, specIndex, interfaceVersion)
    local classPolicy = Registry.classes[classFile]
    local specPolicy = classPolicy and classPolicy.specs and classPolicy.specs[specIndex]
    if not specPolicy then
        return nil
    end

    interfaceVersion = tonumber(interfaceVersion) or getInterfaceVersion()
    local result = {
        classFile = classFile,
        specIndex = specIndex,
        storageKey = classFile .. "_" .. tostring(specIndex),
        id = specPolicy.id or tostring(specIndex),
        name = specPolicy.name or specPolicy.id or tostring(specIndex),
        classRevision = tonumber(classPolicy.revision) or 1,
        revision = tonumber(specPolicy.revision) or 1,
        interfaceVersion = interfaceVersion,
        ruleset = "base",
        reserve = copyArray(specPolicy.reserve),
        moveCastAlways = copyArray(classPolicy.moveCastAlways),
        moveCastBuffs = copyArray(classPolicy.moveCastBuffs),
        clipChannels = copyArray(classPolicy.clipChannels),
        rangeSequenceRules = copyRangeSequenceRules(classPolicy.rangeSequenceRules),
        groundEffects = copyGroundEffects(classPolicy.groundEffects),
    }
    addUniqueValues(result.moveCastAlways, specPolicy.moveCastAlways)
    addUniqueValues(result.moveCastBuffs, specPolicy.moveCastBuffs)
    addUniqueValues(result.clipChannels, specPolicy.clipChannels)
    appendRangeSequenceRules(result.rangeSequenceRules, specPolicy.rangeSequenceRules)
    appendGroundEffects(result.groundEffects, specPolicy.groundEffects)

    local patch = selectVersionPatch(specPolicy, interfaceVersion)
    if patch then
        result.ruleset = patch.id or ("interface-" .. tostring(patch.minInterface or interfaceVersion))
        result.revision = tonumber(patch.revision) or result.revision
        if patch.reserve then
            replaceArray(result.reserve, patch.reserve)
        end
        removeValues(result.reserve, patch.removeReserve)
        addUniqueValues(result.reserve, patch.addReserve)
        if patch.moveCastAlways then
            replaceArray(result.moveCastAlways, patch.moveCastAlways)
        end
        if patch.moveCastBuffs then
            replaceArray(result.moveCastBuffs, patch.moveCastBuffs)
        end
        if patch.clipChannels then
            replaceArray(result.clipChannels, patch.clipChannels)
        end
        if patch.rangeSequenceRules then
            result.rangeSequenceRules = copyRangeSequenceRules(patch.rangeSequenceRules)
        end
        if patch.groundEffects then
            result.groundEffects = copyGroundEffects(patch.groundEffects)
        end
        removeValues(result.moveCastAlways, patch.removeMoveCastAlways)
        addUniqueValues(result.moveCastAlways, patch.addMoveCastAlways)
        removeValues(result.moveCastBuffs, patch.removeMoveCastBuffs)
        addUniqueValues(result.moveCastBuffs, patch.addMoveCastBuffs)
        removeValues(result.clipChannels, patch.removeClipChannels)
        addUniqueValues(result.clipChannels, patch.addClipChannels)
        appendRangeSequenceRules(result.rangeSequenceRules, patch.addRangeSequenceRules)
        appendGroundEffects(result.groundEffects, patch.addGroundEffects)
    end

    return result
end

function Registry.GetInterfaceVersion()
    return getInterfaceVersion()
end
