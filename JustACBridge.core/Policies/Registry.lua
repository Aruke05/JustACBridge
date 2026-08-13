-- Central class-policy registry.
--
-- Class files register stable per-specialization defaults.  Optional version
-- patches let a future game update add/remove/replace spell IDs without
-- touching JustACBridge.lua or invalidating the player's saved overrides.

local Registry = _G.JustACBridgePolicyRegistry or {}
_G.JustACBridgePolicyRegistry = Registry

Registry.schemaVersion = 9
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

local function copyFallbackActions(source)
    local result = {}
    for _, rule in ipairs(source or {}) do
        local spellID = type(rule) == "table" and tonumber(rule.spellID) or tonumber(rule)
        if spellID and spellID > 0 then
            result[#result + 1] = {
                spellID = spellID,
                minEnemies = type(rule) == "table" and tonumber(rule.minEnemies) or nil,
                maxEnemies = type(rule) == "table" and tonumber(rule.maxEnemies) or nil,
                requireProc = type(rule) == "table" and rule.requireProc == true or false,
                label = type(rule) == "table" and rule.label or nil,
            }
        end
    end
    return result
end

local function appendFallbackActions(target, source)
    for _, rule in ipairs(copyFallbackActions(source)) do
        target[#target + 1] = rule
    end
end

local function copyConditionalProtectedChannels(source)
    local result = {}
    for _, rule in ipairs(source or {}) do
        local spellID = type(rule) == "table" and tonumber(rule.spellID) or nil
        if spellID and spellID > 0 then
            result[#result + 1] = {
                spellID = spellID,
                buffs = copyArray(rule.buffs),
                label = rule.label,
            }
        end
    end
    return result
end

local function appendConditionalProtectedChannels(target, source)
    for _, rule in ipairs(copyConditionalProtectedChannels(source)) do
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

-- Register one specialization in its own file.  Class files contain only
-- genuinely class-wide rules; replacing a spec file replaces that spec as a
-- unit without touching siblings or the shared selector.
function Registry.RegisterSpec(classFile, specIndex, definition)
    specIndex = tonumber(specIndex)
    local classPolicy = Registry.classes[classFile]
    if type(classFile) ~= "string" or classFile == "" or not specIndex
        or type(definition) ~= "table" or not classPolicy then
        return false
    end
    classPolicy.specs = classPolicy.specs or {}
    classPolicy.specs[specIndex] = definition
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
        reservePassthrough = copyArray(classPolicy.reservePassthrough),
        reserveExclusions = copyArray(classPolicy.reserveExclusions),
        rotationExclusions = copyArray(classPolicy.rotationExclusions),
        moveCastAlways = copyArray(classPolicy.moveCastAlways),
        moveCastBuffs = copyArray(classPolicy.moveCastBuffs),
        moveCastNever = copyArray(classPolicy.moveCastNever),
        moveCastInstantOnly = copyArray(classPolicy.moveCastInstantOnly),
        clipChannels = copyArray(classPolicy.clipChannels),
        protectedChannels = copyArray(classPolicy.protectedChannels),
        conditionalProtectedChannels = copyConditionalProtectedChannels(
            classPolicy.conditionalProtectedChannels),
        rangeSequenceRules = copyRangeSequenceRules(classPolicy.rangeSequenceRules),
        groundEffects = copyGroundEffects(classPolicy.groundEffects),
        fallbackActions = copyFallbackActions(classPolicy.fallbackActions),
    }
    addUniqueValues(result.reservePassthrough, specPolicy.reservePassthrough)
    addUniqueValues(result.reserveExclusions, specPolicy.reserveExclusions)
    addUniqueValues(result.rotationExclusions, specPolicy.rotationExclusions)
    addUniqueValues(result.moveCastAlways, specPolicy.moveCastAlways)
    addUniqueValues(result.moveCastBuffs, specPolicy.moveCastBuffs)
    addUniqueValues(result.moveCastNever, specPolicy.moveCastNever)
    addUniqueValues(result.moveCastInstantOnly, specPolicy.moveCastInstantOnly)
    addUniqueValues(result.clipChannels, specPolicy.clipChannels)
    addUniqueValues(result.protectedChannels, specPolicy.protectedChannels)
    appendConditionalProtectedChannels(result.conditionalProtectedChannels,
        specPolicy.conditionalProtectedChannels)
    appendRangeSequenceRules(result.rangeSequenceRules, specPolicy.rangeSequenceRules)
    appendGroundEffects(result.groundEffects, specPolicy.groundEffects)
    appendFallbackActions(result.fallbackActions, specPolicy.fallbackActions)

    local patch = selectVersionPatch(specPolicy, interfaceVersion)
    if patch then
        result.ruleset = patch.id or ("interface-" .. tostring(patch.minInterface or interfaceVersion))
        result.revision = tonumber(patch.revision) or result.revision
        if patch.reserve then
            replaceArray(result.reserve, patch.reserve)
        end
        removeValues(result.reserve, patch.removeReserve)
        addUniqueValues(result.reserve, patch.addReserve)
        if patch.reservePassthrough then
            replaceArray(result.reservePassthrough, patch.reservePassthrough)
        end
        if patch.reserveExclusions then
            replaceArray(result.reserveExclusions, patch.reserveExclusions)
        end
        if patch.rotationExclusions then
            replaceArray(result.rotationExclusions, patch.rotationExclusions)
        end
        if patch.moveCastAlways then
            replaceArray(result.moveCastAlways, patch.moveCastAlways)
        end
        if patch.moveCastBuffs then
            replaceArray(result.moveCastBuffs, patch.moveCastBuffs)
        end
        if patch.moveCastNever then
            replaceArray(result.moveCastNever, patch.moveCastNever)
        end
        if patch.moveCastInstantOnly then
            replaceArray(result.moveCastInstantOnly, patch.moveCastInstantOnly)
        end
        if patch.clipChannels then
            replaceArray(result.clipChannels, patch.clipChannels)
        end
        if patch.protectedChannels then
            replaceArray(result.protectedChannels, patch.protectedChannels)
        end
        if patch.conditionalProtectedChannels then
            result.conditionalProtectedChannels = copyConditionalProtectedChannels(
                patch.conditionalProtectedChannels)
        end
        if patch.rangeSequenceRules then
            result.rangeSequenceRules = copyRangeSequenceRules(patch.rangeSequenceRules)
        end
        if patch.groundEffects then
            result.groundEffects = copyGroundEffects(patch.groundEffects)
        end
        if patch.fallbackActions then
            result.fallbackActions = copyFallbackActions(patch.fallbackActions)
        end
        removeValues(result.reservePassthrough, patch.removeReservePassthrough)
        addUniqueValues(result.reservePassthrough, patch.addReservePassthrough)
        removeValues(result.reserveExclusions, patch.removeReserveExclusions)
        addUniqueValues(result.reserveExclusions, patch.addReserveExclusions)
        removeValues(result.rotationExclusions, patch.removeRotationExclusions)
        addUniqueValues(result.rotationExclusions, patch.addRotationExclusions)
        removeValues(result.moveCastAlways, patch.removeMoveCastAlways)
        addUniqueValues(result.moveCastAlways, patch.addMoveCastAlways)
        removeValues(result.moveCastBuffs, patch.removeMoveCastBuffs)
        addUniqueValues(result.moveCastBuffs, patch.addMoveCastBuffs)
        removeValues(result.moveCastNever, patch.removeMoveCastNever)
        addUniqueValues(result.moveCastNever, patch.addMoveCastNever)
        removeValues(result.moveCastInstantOnly, patch.removeMoveCastInstantOnly)
        addUniqueValues(result.moveCastInstantOnly, patch.addMoveCastInstantOnly)
        removeValues(result.clipChannels, patch.removeClipChannels)
        addUniqueValues(result.clipChannels, patch.addClipChannels)
        removeValues(result.protectedChannels, patch.removeProtectedChannels)
        addUniqueValues(result.protectedChannels, patch.addProtectedChannels)
        appendConditionalProtectedChannels(result.conditionalProtectedChannels,
            patch.addConditionalProtectedChannels)
        appendRangeSequenceRules(result.rangeSequenceRules, patch.addRangeSequenceRules)
        appendGroundEffects(result.groundEffects, patch.addGroundEffects)
        appendFallbackActions(result.fallbackActions, patch.addFallbackActions)
    end

    return result
end

function Registry.GetInterfaceVersion()
    return getInterfaceVersion()
end
