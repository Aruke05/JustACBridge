-- Identity of the currently selected target, NOT a guessed/cached GUID.
-- Explicit opt-in only. Core must Reset on PLAYER_TARGET_CHANGED (synchronous),
-- world/spec/talent/combat resets. Every read rechecks current target validity.
local Lease = {}
_G.JustACBridgeTargetLease = Lease
local State = {}
State.__index = State
local function plain(v, kind)
    return not (issecretvalue and issecretvalue(v)) and type(v) == kind
end
local function read(fn, kind, ...)
    if type(fn) ~= "function" then return nil, "missing" end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, "error" end
    if issecretvalue and issecretvalue(value) then return nil, "secret" end
    if not plain(value, kind) then return nil, "unknown" end
    if kind == "string" then
        if value == "" then return nil, "empty" end
        return value, "readable"
    end
    return value, tostring(value)
end
function Lease.New() return setmetatable({}, State) end
function State:Reset() self.key, self.guid = nil, nil end
function State:Read()
    local exists, e = read(UnitExists, "boolean", "target")
    local attackable, a = read(UnitCanAttack, "boolean", "player", "target")
    local dead, d = read(UnitIsDeadOrGhost, "boolean", "target")
    local guid, g = read(UnitGUID, "string", "target")
    local evidence = "exists=" .. e .. ",attackable=" .. a .. ",dead=" .. d .. ",guid=" .. g
    local valid
    if exists == false or attackable == false or dead == true then valid = false
    elseif exists == true and attackable == true and dead == false then valid = true end
    if valid == false then
        self:Reset()
    else
        -- Extra defense for a readable GUID discontinuity. A hidden GUID is
        -- never compared, serialized, fabricated, or treated as no target.
        if guid and self.guid and guid ~= self.guid then self:Reset() end
        if guid then self.guid = guid end
        if valid == true and not self.key then self.key = {} end
        -- Unknown validity grants NO action permission. An existing receipt
        -- can still accept a successful player cast during this same epoch;
        -- the selector must WAIT until validity is positively restored.
    end
    return {key = self.key, valid = valid, evidence = evidence}
end
