-- Shared, specialization-neutral runtime for the independent 12.1 sources.
--
-- This file contains observation plumbing only.  It deliberately has no APL,
-- class spell IDs, thresholds, or priorities; those stay inside each spec file
-- so one branch can never silently change another branch's rotation.

local Runtime = _G.JustACBridge121Runtime or {}
_G.JustACBridge121Runtime = Runtime

local function isPlain(value, kind)
    if type(value) ~= kind then return false end
    return not (issecretvalue and issecretvalue(value))
end

local function now()
    return GetTime and GetTime() or 0
end

local function appendFallback(first, raw)
    local result, seen = {}, {}
    if type(first) == "number" and first ~= 0 then
        result[1], seen[first] = first, true
    end
    for index = 1, #raw do
        local value = raw[index]
        if type(value) == "number" and value ~= 0 and not seen[value] then
            result[#result + 1], seen[value] = value, true
        end
    end
    return result
end

function Runtime.New(owner, classFile, specializationIndex, gcdSpells)
    local context = {
        owner = owner,
        classFile = classFile,
        specializationIndex = specializationIndex,
        gcdSpells = gcdSpells or {},
        castAt = {},
        gcdHistory = {},
        decision = "uninitialized",
    }

    function context:Initialize(onEvent)
        local libStub = _G.LibStub
        if not libStub then return false, "LibStub unavailable" end
        self.SpellQueue = libStub("JustAC-SpellQueue", true)
        self.BlizzardAPI = libStub("JustAC-BlizzardAPI", true)
        if not self.SpellQueue then return false, "JustAC-SpellQueue unavailable" end
        if not self.BlizzardAPI then return false, "JustAC-BlizzardAPI unavailable" end

        local frame = CreateFrame and CreateFrame("Frame")
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_DISABLED")
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            frame:SetScript("OnEvent", function(_, event, _, _, spellID)
                if event == "PLAYER_REGEN_DISABLED" then
                    self.combatStartedAt = now()
                    self.gcdHistory = {}
                    if onEvent then pcall(onEvent, self, event) end
                    return
                end
                if event == "PLAYER_REGEN_ENABLED" then
                    self.combatStartedAt = nil
                    self.castAt = {}
                    self.gcdHistory = {}
                    if onEvent then pcall(onEvent, self, event) end
                    return
                end

                spellID = tonumber(spellID)
                if not spellID then return end
                self.castAt[spellID] = now()
                if self.gcdSpells[spellID] then
                    table.insert(self.gcdHistory, 1, spellID)
                    while #self.gcdHistory > 3 do table.remove(self.gcdHistory) end
                end
                if onEvent then pcall(onEvent, self, event, spellID) end
            end)
            self.eventFrame = frame
        end
        return true
    end

    function context:IsAvailable()
        return self.SpellQueue ~= nil and self.BlizzardAPI ~= nil
    end

    function context:InScope()
        if not UnitClass then return false end
        local _, actualClass = UnitClass("player")
        local actualSpec = GetSpecialization and GetSpecialization()
        local interface = GetBuildInfo and select(4, GetBuildInfo())
        return actualClass == self.classFile and actualSpec == self.specializationIndex
            and isPlain(interface, "number")
            and interface >= 120100 and interface <= 120199
    end

    function context:InCombat()
        if not UnitAffectingCombat then return false end
        local ok, value = pcall(UnitAffectingCombat, "player")
        return ok and isPlain(value, "boolean") and value == true
    end

    function context:CombatAge()
        if not self.combatStartedAt then return nil end
        return math.max(0, now() - self.combatStartedAt)
    end

    function context:HasHostileTarget()
        if not (UnitExists and UnitCanAttack) then return false end
        local okExists, exists = pcall(UnitExists, "target")
        local okAttack, attackable = pcall(UnitCanAttack, "player", "target")
        return okExists and isPlain(exists, "boolean") and exists == true
            and okAttack and isPlain(attackable, "boolean") and attackable == true
    end

    function context:RawQueue()
        local ok, raw = pcall(self.SpellQueue.GetCurrentSpellQueue)
        return ok and type(raw) == "table" and raw or {}
    end

    function context:CallBoolean(method, ...)
        local fn = self.BlizzardAPI and self.BlizzardAPI[method]
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if not ok or not isPlain(value, "boolean") then return nil end
        return value
    end

    function context:Ready(spellID)
        -- Usable/cooldown wrappers are not proof that the player owns an
        -- action: in live 12.1 they can report a plain usable value for a
        -- talent spell which is absent from the current build.  Requiring an
        -- authoritative spellbook/talent result prevents a source from
        -- inventing actions such as Comet Storm for a Frost build that does
        -- not have it.
        if not self:Known(spellID) then return false end
        local usable = self:CallBoolean("IsSpellUsable", spellID)
        local cooldown = self:CallBoolean("IsSpellOnCooldown", spellID)
        if usable == nil or cooldown == nil then return nil end
        return usable and not cooldown
    end

    function context:Procced(spellID)
        return self:CallBoolean("IsSpellProcced", spellID)
    end

    function context:AtMaxCharges(spellID)
        return self:CallBoolean("IsSpellAtMaxCharges", spellID)
    end

    function context:AuraAtLeast(unit, spellID, stacks)
        local fn = self.BlizzardAPI and self.BlizzardAPI.GetAuraStackAtLeast
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, unit, spellID, stacks)
        if not ok or not isPlain(value, "boolean") then return nil end
        return value
    end

    function context:AuraUp(unit, spellID)
        return self:AuraAtLeast(unit, spellID, 1)
    end

    -- Player aura duration predicates are laundered by JustAC's duration
    -- curve helper.  The function never reads a secret number: it returns a
    -- plain boolean or nil when the aura instance/duration cannot be trusted.
    function context:PlayerAuraRemainsBelow(spellID, seconds)
        if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                and self.BlizzardAPI and self.BlizzardAPI.GetAuraDurationObject
                and self.BlizzardAPI.IsDurationBelowSeconds) then
            return nil
        end
        local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if not okAura or not aura or not isPlain(aura.auraInstanceID, "number") then
            return nil
        end
        local okDuration, duration = pcall(self.BlizzardAPI.GetAuraDurationObject,
            "player", aura.auraInstanceID)
        if not okDuration or not duration then return nil end
        local okBelow, below = pcall(self.BlizzardAPI.IsDurationBelowSeconds,
            duration, seconds)
        if okBelow and isPlain(below, "boolean") then return below end
        return nil
    end

    -- A successful cast proves a minimum, non-extendable part of an aura is
    -- active.  Outside that interval we go back to the live aura predicate;
    -- no guessed expiry is ever used to prove that the aura is absent.
    function context:AuraUpOrRecentCast(auraID, castID, minimumSeconds)
        local castTime = self.castAt[castID]
        local age = castTime and now() - castTime or nil
        if age and age >= 0 and age < minimumSeconds then return true end
        return self:AuraUp("player", auraID)
    end

    function context:Known(spellID)
        for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown }) do
            if type(fn) == "function" then
                local ok, value = pcall(fn, spellID)
                if ok and isPlain(value, "boolean") and value == true then return true end
            end
        end
        return false
    end

    function context:Display(spellID)
        local fn = self.BlizzardAPI and self.BlizzardAPI.GetDisplaySpellID
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, spellID)
        return ok and isPlain(value, "number") and value or nil
    end

    function context:Resource(expectedResource)
        local fn = self.BlizzardAPI and self.BlizzardAPI.GetClassResourcePoints
        if type(fn) ~= "function" then return nil, nil end
        local ok, current, maximum, resource = pcall(fn)
        if not ok or not isPlain(current, "number") or not isPlain(maximum, "number")
            or resource ~= expectedResource then
            return nil, nil
        end
        return current, maximum
    end

    function context:EnemyCount()
        local fn = self.BlizzardAPI and self.BlizzardAPI.GetEngagedEnemyCount
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn)
        if not ok or not isPlain(value, "number") then return nil end
        value = math.max(0, math.floor(value))
        -- A valid hostile target is one certain enemy even before its nameplate
        -- threat token reaches JustAC's 250 ms cache.
        if value == 0 and self:HasHostileTarget() then value = 1 end
        return value
    end

    function context:HealthBelow(unit, percent)
        local fn = self.BlizzardAPI and self.BlizzardAPI.IsUnitHealthBelow
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, unit, percent)
        if not ok or not isPlain(value, "boolean") then return nil end
        return value
    end

    function context:PowerBelow(unit, percent, powerType)
        local fn = self.BlizzardAPI and self.BlizzardAPI.IsUnitPowerBelow
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, unit, percent, powerType)
        if not ok or not isPlain(value, "boolean") then return nil end
        return value
    end

    function context:PreviousGCD(position)
        return self.gcdHistory[position or 1]
    end

    function context:CastAge(spellID)
        local castTime = self.castAt[spellID]
        return castTime and math.max(0, now() - castTime) or nil
    end

    function context:Choose(spellID, rule, detail, raw)
        self.decision = ("owner=%s action=%s rule=%s detail=%s fallback=false")
            :format(self.owner, tostring(spellID), tostring(rule), tostring(detail or "ok"))
        return appendFallback(spellID, raw)
    end

    function context:Fallback(reason, raw)
        self.decision = ("owner=%s action=nil rule=fallback.justac reason=%s fallback=true")
            :format(self.owner, tostring(reason or "no-proven-action"))
        return raw
    end

    return context
end

Runtime.AppendFallback = appendFallback
