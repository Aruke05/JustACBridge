-- Current BM charge/priority matrix. Each test reads fresh API state.
local now, haste, enemies, focus = 100, 0, 1, 100
local raw = {217200, 193455, 34026}
local known, bindings, usable, cooldown, charges, auras, auraTimes = {}, {}, {}, {}, {}, {}, {}
local secret = {}
local frames = {}
local equippedPieces=4
local tierSlots={[1]=1,[3]=2,[5]=3,[7]=4,[10]=5}
function GetInventoryItemID(unit,slot)
    assert(unit=="player")
    local index=tierSlots[slot]
    return index and index<=equippedPieces and 270000+index or nil
end
C_Item={GetSetBonusesForSpecializationByItemID=function(spec,id)
    assert(spec==253 and id>=270001 and id<=270005)
    return {1296631,1296632}
end}
function issecretvalue(v) return v == secret end
function GetTime() return now end
function GetHaste() return haste end
function UnitPower(_, power) assert(power == 2); return focus end
function UnitClass() return "Hunter", "HUNTER" end
function GetSpecialization() return 1 end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function UnitAffectingCombat() return true end
function UnitExists() return true end
function UnitCanAttack() return true end
function IsPlayerSpell(id) return known[id] end
function IsSpellKnown(id) return known[id] end
function CreateFrame()
    local f = { RegisterEvent=function() end, RegisterUnitEvent=function() end,
        SetScript=function(self, _, fn) self.OnEvent=fn end,
        GetScript=function(self) return self.OnEvent end }
    frames[#frames+1]=f; return f
end
local function duration(value)
    return {GetRemainingDuration=function() return value end}
end
C_Spell = {
    IsSpellUsable=function(id) return usable[id], false end,
    GetSpellCooldownDuration=function(id, ignoreGCD)
        assert(ignoreGCD == true); if cooldown[id] ~= nil then return duration(cooldown[id]) end
    end,
    GetSpellCharges=function(id) return charges[id] end,
}
C_UnitAuras = { GetPlayerAuraBySpellID=function(id)
    if auras[id] == true then return {auraInstanceID=id} end
end }
local api = {
    IsSpellReady=function(id)
        local c=charges[id]; if c and type(c.currentCharges)=="number" then return c.currentCharges>0 end
    end,
    -- Deliberately wrong for charged spells: a recovery timer is always active.
    IsSpellOnCooldown=function() return true end,
    IsSpellUsable=function() return true end,
    IsSpellAtMaxCharges=function(id)
        local c=charges[id]; if c and type(c.currentCharges)=="number" then return c.currentCharges==c.maxCharges end
    end,
    GetAuraStackAtLeast=function(_,id,threshold)
        local v=auras[id]; if v == secret then return secret end
        if type(v)=="number" then return v>=threshold end
        return v
    end,
    GetAuraDurationObject=function(_,id) return duration(auraTimes[id]) end,
    GetEngagedEnemyCount=function() return enemies end,
}
local scanner={GetSpellHotkey=function(id) return bindings[id] end}
LibStub=function(name)
    if name=="JustAC-SpellQueue" then return {GetCurrentSpellQueue=function() return raw end} end
    if name=="JustAC-BlizzardAPI" then return api end
    if name=="JustAC-ActionBarScanner" then return scanner end
end
-- Match production LibStub: callable TABLE, not just a function-shaped mock.
local lookupLibrary = LibStub
LibStub = setmetatable({}, {__call=function(_, ...) return lookupLibrary(...) end})
assert(type(LibStub)=="table")
dofile("JustACBridge.core/Framework/ActionSequence.lua")
dofile("JustACBridge.core/Framework/ResourcePreparation.lua")
dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/Runtime121.lua")
dofile("JustACBridge.core/Sources/BeastMasteryHunter121.lua")
local bm=assert(JustACBridgeRecommendationSources.Get("bmhunter121"))
local S=bm._Test.spell
local frame=bm._Test.context.eventFrame
local count=0
local function charge(id,n,remaining,maximum,total)
    total=total or 10
    charges[id]={currentCharges=n,maxCharges=maximum or 2,
        cooldownStartTime=now-(total-(remaining or 5)), cooldownDuration=total,chargeModRate=1}
end
local function reset()
    now,haste,enemies,focus=100,0,1,100
    equippedPieces=4
    raw={217200,193455,34026}
    known,bindings,usable,cooldown,charges,auras,auraTimes={},{},{},{},{},{},{}
    for _,id in pairs(S) do known[id]=false; bindings[id]="1"; usable[id]=true; cooldown[id]=30; auras[id]=false end
    for _,id in ipairs({S.BARBED_SHOT,S.KILL_COMMAND,S.COBRA_SHOT,S.BESTIAL_WRATH,
        S.WILD_THRASH,S.HOWL_OF_THE_PACK_LEADER_TALENT,S.NATURES_ALLY_TALENT,S.SERPENTINE_STRIKES}) do known[id]=true end
    cooldown[S.COBRA_SHOT]=0
    charge(S.BARBED_SHOT,1,5); charge(S.KILL_COMMAND,1,5)
    auras[S.NATURES_ALLY]=true
    auras[S.HOWL_COOLDOWN]=true; auraTimes[S.HOWL_COOLDOWN]=20
    frame.OnEvent(frame,"PLAYER_ENTERING_WORLD")
    frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","baseline-cobra",S.COBRA_SHOT)
end
local function selected(id, rule)
    local q=bm.GetQueue(); assert(q[1]==id, bm.GetDecisionTrace())
    assert(bm.GetDecisionTrace():match("fallback=false"), bm.GetDecisionTrace())
    if rule then assert(bm.GetDecisionTrace():find(rule,1,true),bm.GetDecisionTrace()) end
    assert(bm.GetPreserveQueue()==raw,"M4 must remain the exact raw queue")
    count=count+1
end
local function delegated(reason)
    assert(bm.GetQueue()==raw,"fallback must return the same queue")
    assert(bm.GetDecisionTrace():match("fallback=true"),bm.GetDecisionTrace())
    if reason then assert(bm.GetDecisionTrace():find(reason,1,true),bm.GetDecisionTrace()) end
    count=count+1
end

-- Readiness: 1/2 is usable even though recharge IsSpellOnCooldown=true.
reset(); assert(bm._Test.ready(S.BARBED_SHOT)==true); assert(bm._Test.ready(S.KILL_COMMAND)==true)
charge(S.KILL_COMMAND,0,5); assert(bm._Test.ready(S.KILL_COMMAND)==false)
charge(S.KILL_COMMAND,2,5); assert(bm._Test.ready(S.KILL_COMMAND)==true)
-- 0/2 requires TWO recharge segments, 1/2 one; no fabricated cap.
charge(S.KILL_COMMAND,0,5); assert(bm._Test.chargeState(S.KILL_COMMAND).full==15)
charge(S.KILL_COMMAND,1,5); assert(bm._Test.chargeState(S.KILL_COMMAND).full==5)
charge(S.KILL_COMMAND,2,5); assert(bm._Test.chargeState(S.KILL_COMMAND).full==0)

-- All ready, then current charges change after each success (not predicted).
reset(); cooldown[S.BESTIAL_WRATH]=0; charge(S.BARBED_SHOT,2)
selected(S.BARBED_SHOT)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bs1",S.BARBED_SHOT)
charge(S.BARBED_SHOT,1); selected(S.BARBED_SHOT)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bs2",S.BARBED_SHOT)
charge(S.BARBED_SHOT,0); selected(S.BESTIAL_WRATH)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bw",S.BESTIAL_WRATH)
cooldown[S.BESTIAL_WRATH]=30; charge(S.BARBED_SHOT,1); auras[S.HOWL_BEAR]=true
selected(S.KILL_COMMAND,"howl-ready")
-- Repeated calls do not consume a buff; success alone does not establish one.
selected(S.KILL_COMMAND,"howl-ready")
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","kc",S.KILL_COMMAND)
auras[S.HOWL_BEAR],auras[S.NATURES_ALLY]=false,false
selected(S.BARBED_SHOT,"serpentine")
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bs3",S.BARBED_SHOT)
auras[S.NATURES_ALLY]=secret; delegated("kill-command-predicates")
auras[S.NATURES_ALLY]=true; selected(S.KILL_COMMAND)

-- Every Howl beast is recognized. A summoned beast aura/glow is NOT readiness.
for _,id in ipairs({S.HOWL_OF_THE_PACK_LEADER,S.HOWL_BOAR,S.HOWL_BEAR}) do
    reset(); auras[S.NATURES_ALLY]=false; auras[id]=true; selected(S.KILL_COMMAND,"howl-ready")
end
reset(); auras[471881]=true; auras[S.NATURES_ALLY]=false; selected(S.BARBED_SHOT)
-- Charge-cap prevention outranks both strengthened Kill and ready Howl.
reset(); charge(S.BARBED_SHOT,2); selected(S.BARBED_SHOT,"charge-cap")
for _,r in ipairs({1.499,1.5,1.501}) do
    reset(); charge(S.BARBED_SHOT,1,r)
    selected(r<1.5 and S.BARBED_SHOT or S.KILL_COMMAND)
end
-- Exact dynamic GCD, including non-integer haste and 0.75 floor.
for _,h in ipairs({13.7,33.3,100,150}) do
    local g=math.max(.75,1.5/(1+h/100))
    for _,offset in ipairs({-.0001,0,.0001}) do
        reset(); haste=h; charge(S.BARBED_SHOT,1,g+offset)
        -- Timestamp subtraction can round an exact floating boundary. The
        -- expected side is the ACTUAL freshly observed full_recharge_time.
        local actual=bm._Test.chargeState(S.BARBED_SHOT).full
        selected(actual<g and S.BARBED_SHOT or S.KILL_COMMAND)
    end
end
-- Nature's Ally needs current BW-vs-full-KC timing AND Howl charge bank.
for _,r in ipairs({6.499,6.5,6.501}) do
    reset(); cooldown[S.BESTIAL_WRATH]=r
    selected(r>6.5 and S.KILL_COMMAND or S.BARBED_SHOT)
end
reset(); auraTimes[S.HOWL_COOLDOWN]=4; selected(S.BARBED_SHOT)
auraTimes[S.HOWL_COOLDOWN]=4.001; selected(S.KILL_COMMAND)
reset(); auraTimes[S.HOWL_COOLDOWN]=1; charge(S.KILL_COMMAND,2); selected(S.KILL_COMMAND)
reset(); auraTimes[S.HOWL_COOLDOWN]=1; charge(S.KILL_COMMAND,1,1.999); selected(S.KILL_COMMAND)
reset(); auraTimes[S.HOWL_COOLDOWN]=1; charge(S.KILL_COMMAND,1,2.001); selected(S.BARBED_SHOT)
-- Without Serpentine, Focus<75 is exact, not a guessed percent/resource cache.
reset(); known[S.SERPENTINE_STRIKES]=false; auras[S.NATURES_ALLY]=false
focus=74; selected(S.BARBED_SHOT)
focus=75; selected(S.COBRA_SHOT)
focus=secret; delegated("focus-talents")
-- Visible Cobra Fang spends only after higher rows have been excluded.
reset(); auras[S.NATURES_ALLY]=false; auras[S.COBRA_FANG]=4; selected(S.COBRA_SHOT)
charge(S.BARBED_SHOT,2); selected(S.BARBED_SHOT)

-- AoE: update/reapply Cleave first, then cap, BW alignment, empowered Kill.
reset(); enemies=4; known[S.BEAST_CLEAVE_TALENT]=true; cooldown[S.WILD_THRASH]=0
selected(S.WILD_THRASH,"beast-cleave-down")
auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6; known[S.MASTER_HANDLER]=true
selected(S.KILL_COMMAND)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bw",S.BESTIAL_WRATH)
selected(S.WILD_THRASH,"previous-gcd")
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","thrash",S.WILD_THRASH)
selected(S.KILL_COMMAND)
-- Trait-specific >=4 target exception does not impose a blind alternation.
auras[S.NATURES_ALLY]=false; selected(S.KILL_COMMAND,"master-handler")
enemies=3; delegated() -- lower Barbed target_if belongs to JustAC
-- Both near-full resources: Barbed's higher target_if is NOT overridden by KC.
reset(); enemies=4; known[S.BEAST_CLEAVE_TALENT]=true
known[S.MASTER_HANDLER]=true; auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6
charge(S.BARBED_SHOT,2); charge(S.KILL_COMMAND,2); delegated("target-if")
-- Cleave barely alive isn't proof that Kill/Cobra may land in its window.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true; auras[S.BEAST_CLEAVE]=true
for _,r in ipairs({.3749,.375,.3751}) do
    auraTimes[S.BEAST_CLEAVE]=r
    if r>.375 then selected(S.KILL_COMMAND) else delegated() end
end
-- Fix: cannot start BW with a distant/unknown Thrash cooldown.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true; auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6
cooldown[S.BESTIAL_WRATH]=0; charge(S.BARBED_SHOT,0)
for _,r in ipairs({0,1.499,1.5,10}) do
    cooldown[S.WILD_THRASH]=r
    if r<1.5 then selected(S.BESTIAL_WRATH,"aligned") else selected(S.KILL_COMMAND) end
end
cooldown[S.WILD_THRASH]=secret; delegated("readiness-unknown")
-- Physical Thrash ID and its successful cast advance the same GCD history.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true; known[S.WILD_THRASH_BASE]=true
cooldown[S.WILD_THRASH_BASE]=0; selected(S.WILD_THRASH_BASE)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","thrash-base",S.WILD_THRASH_BASE)
assert(bm._Test.context:PreviousGCD(1)==S.WILD_THRASH_BASE)

-- Ownership/binding/affordability are not the fail-open upstream bits.
for _,id in ipairs({S.KILL_COMMAND,S.BARBED_SHOT,S.BESTIAL_WRATH}) do
    reset(); known[id]=false; assert(bm._Test.ready(id)==false)
    reset(); known[id]=secret; delegated()
    reset(); bindings[id]=""; assert(bm._Test.ready(id)==false)
    reset(); bindings[id]=nil; delegated()
    reset(); usable[id]=false; assert(bm._Test.ready(id)==false)
    reset(); usable[id]=secret; delegated("readiness-unknown")
end
-- Missing/nil/secret/exception evidence must not reorder any raw tail.
reset(); raw={193455,34026,217200}
local old=C_Spell.GetSpellCharges
for _,fn in ipairs({function() return nil end,function() return secret end,function() error("charge fault") end}) do
    C_Spell.GetSpellCharges=fn
    local oldReady=api.IsSpellReady; api.IsSpellReady=function() return nil end
    delegated("readiness-unknown"); api.IsSpellReady=oldReady
end
C_Spell.GetSpellCharges=old
reset(); charges[S.BARBED_SHOT].cooldownStartTime=secret; delegated("recharge-window")
reset(); charges[S.BARBED_SHOT].chargeModRate=secret; delegated("recharge-window")
reset(); charges[S.BARBED_SHOT].chargeModRate=2; delegated("recharge-window")
reset(); charges[S.BARBED_SHOT].cooldownStartTime=now+1; delegated("recharge-window")
reset(); charges[S.BARBED_SHOT].cooldownDuration=0; delegated("recharge-window")
reset(); haste=secret; delegated("recharge-window")
reset(); auras[S.HOWL_OF_THE_PACK_LEADER]=secret; auras[S.NATURES_ALLY]=false; delegated("kill-command-predicates")
reset(); auras[S.HOWL_COOLDOWN]=true; auraTimes[S.HOWL_COOLDOWN]=secret; delegated("kill-command-predicates")
reset(); known[S.BLACK_ARROW_TALENT]=true; delegated("dark-ranger")
reset(); raw={}; auras[S.HOWL_BEAR]=secret; auras[S.NATURES_ALLY]=false; delegated()
reset(); raw={-123,34026}; delegated("active-item")

-- Recompute on each frame; no success event, target switch or failed attempt
-- can manufacture current Nature/Howl evidence or resurrect a previous GCD.
for _,event in ipairs({"PLAYER_TARGET_CHANGED","PLAYER_ENTERING_WORLD","PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED"}) do
    reset(); frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bw",S.BESTIAL_WRATH)
    assert(bm._Test.context:PreviousGCD(1)==S.BESTIAL_WRATH)
    frame.OnEvent(frame,event,"player"); assert(bm._Test.context:PreviousGCD(1)==nil)
end
reset(); frame.OnEvent(frame,"PLAYER_ENTERING_WORLD"); frame.OnEvent(frame,"UNIT_SPELLCAST_FAILED","player","fail",S.BESTIAL_WRATH)
assert(bm._Test.context:PreviousGCD(1)==nil)
-- A missing/invalidated previous GCD cannot disprove the highest Thrash row.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true
cooldown[S.WILD_THRASH]=0; auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6
frame.OnEvent(frame,"PLAYER_TARGET_CHANGED"); delegated("previous-gcd-unknown")
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","cobra",S.COBRA_SHOT)
selected(S.KILL_COMMAND)
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","utility",999001)
delegated("previous-gcd-unknown")
frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","pet","not-player",S.BESTIAL_WRATH)
assert(bm._Test.context:PreviousGCD(1)==nil)
-- Without Cleave talent, Fang alone is NOT the high-priority AoE Cobra row.
reset(); enemies=3; auras[S.NATURES_ALLY]=false; auras[S.COBRA_FANG]=1
delegated("target-if")
-- Either authoritative ownership API can prove an action; no nil-array hole.
reset(); local saved=IsPlayerSpell; IsPlayerSpell=nil
assert(bm._Test.ready(S.KILL_COMMAND)==true); IsPlayerSpell=saved
-- After actual BW success: exhaustive finite current-state combinations.
-- No inferred buff, charge gain or consumption comes from that success.
for bs=0,2 do
    for kc=0,2 do
        for _,nature in ipairs({false,true}) do
            for _,howl in ipairs({false,true}) do
                reset()
                frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bw-matrix",S.BESTIAL_WRATH)
                cooldown[S.BESTIAL_WRATH]=30
                charge(S.BARBED_SHOT,bs,5); charge(S.KILL_COMMAND,kc,5)
                auras[S.NATURES_ALLY],auras[S.HOWL_BEAR]=nature,howl
                -- BW=30 and Howl CD=20 exclude all timing/banking obstacles.
                if bs==2 then selected(S.BARBED_SHOT)
                elseif kc>0 and (nature or howl) then selected(S.KILL_COMMAND)
                elseif bs>0 then selected(S.BARBED_SHOT)
                else selected(S.COBRA_SHOT) end
            end
        end
    end
end
for _,targets in ipairs({2,3,4}) do
    for bs=0,2 do
        for kc=0,2 do
            for _,nature in ipairs({false,true}) do
                for _,howl in ipairs({false,true}) do
                    for _,master in ipairs({false,true}) do
                        reset(); enemies=targets; known[S.BEAST_CLEAVE_TALENT]=true
                        frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","bw-matrix",S.BESTIAL_WRATH)
                        frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","thrash-matrix",S.WILD_THRASH)
                        cooldown[S.BESTIAL_WRATH]=30; cooldown[S.WILD_THRASH]=30
                        auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6
                        charge(S.BARBED_SHOT,bs,5); charge(S.KILL_COMMAND,kc,5)
                        auras[S.NATURES_ALLY],auras[S.HOWL_BEAR]=nature,howl
                        known[S.MASTER_HANDLER]=master
                        if bs==2 then delegated("target-if")
                        elseif kc>0 and (nature or master and (targets>=4 or howl)) then selected(S.KILL_COMMAND)
                        elseif bs>0 then delegated("target-if")
                        else selected(S.COBRA_SHOT) end
                    end
                end
            end
        end
    end
end
-- !apex.3 is a real talent exception, not a fabricated Nature buff.
reset(); known[S.NATURES_ALLY_TALENT]=false; auras[S.NATURES_ALLY]=false
selected(S.KILL_COMMAND)
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true; known[S.NATURES_ALLY_TALENT]=false
auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6; auras[S.NATURES_ALLY]=false
selected(S.KILL_COMMAND)
-- Invalid counters do not select a single/cleave table by accidental comparison.
reset(); enemies=0/0; delegated("enemy-count-unknown")
reset(); enemies=math.huge; delegated("enemy-count-unknown")
-- Unexpected scope/aura-duration object faults still keep the exact raw queue.
reset(); local oldClass=UnitClass; UnitClass=function() error("scope fault") end
delegated("bm-current-evidence-error"); UnitClass=oldClass
reset(); local oldAura=api.GetAuraDurationObject
api.GetAuraDurationObject=function() return setmetatable({}, {__index=function() error("duration method fault") end}) end
delegated("kill-command-predicates"); api.GetAuraDurationObject=oldAura
-- Adversarial mixed evidence: a wrapper must not contradict current native
-- 1/2 charges just because native recharge timestamps are unavailable.
reset(); local oldMax=api.IsSpellAtMaxCharges
charges[S.BARBED_SHOT].cooldownStartTime=secret
api.IsSpellAtMaxCharges=function() return true end
delegated("recharge-window")
api.IsSpellAtMaxCharges=oldMax
reset(); charges[S.KILL_COMMAND].cooldownStartTime=secret
api.IsSpellAtMaxCharges=function() return true end
delegated("kill-command-predicates")
api.IsSpellAtMaxCharges=oldMax
-- Unlike the first ST Barbed row, the lower ST row has NO target_if.
reset(); enemies=2; known[S.BEAST_CLEAVE_TALENT]=false
auras[S.NATURES_ALLY]=false
selected(S.BARBED_SHOT,"serpentine")
-- An aura still listed at its expiry is not positive remaining duration.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true
auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=0
cooldown[S.BESTIAL_WRATH]=0; cooldown[S.WILD_THRASH]=1; charge(S.BARBED_SHOT,0)
delegated()
-- Exact equality must not spend the Howl-banked Kill charge.
reset(); auraTimes[S.HOWL_COOLDOWN]=1; charge(S.KILL_COMMAND,1,2)
selected(S.BARBED_SHOT)

-- An unbound near-ready BW does not authorize skipping the top Barbed row
-- to inject Fang Cobra. Far BW can still exclude that row without guessing.
reset(); bindings[S.BESTIAL_WRATH]=""; cooldown[S.BESTIAL_WRATH]=.5; auras[S.COBRA_FANG]=4
auras[S.NATURES_ALLY]=false
delegated("recharge-window")
cooldown[S.BESTIAL_WRATH]=30; selected(S.COBRA_SHOT,"cobra-fang")
-- Current tier count + BM-specific set spell, with no gear cache or aura inference.
for _,pieces in ipairs({0,2,3,4,5}) do
    reset(); equippedPieces=pieces; auras[S.NATURES_ALLY]=false; auras[S.COBRA_FANG]=4
    if pieces>=4 then selected(S.COBRA_SHOT,"cobraSet=4pc")
    else delegated("cobra-fang-equipment-conflict"); assert(bm.GetDecisionTrace():find(pieces>=2 and "cobraSet=2pc" or "cobraSet=none",1,true)) end
end
reset(); auras[S.NATURES_ALLY]=false; auras[S.COBRA_FANG]=4
local oldBonuses=C_Item.GetSetBonusesForSpecializationByItemID
for _,fn in ipairs({function() return nil end,function() return secret end,function() error("item data fault") end,
    function() return {1296631,secret} end}) do
    C_Item.GetSetBonusesForSpecializationByItemID=fn; delegated("cobra-fang-equipment-unknown")
end
C_Item.GetSetBonusesForSpecializationByItemID=function() return {1296633,1296634} end
-- Other Hunter specialization / wrong set does not grant BM four-piece.
delegated("cobra-fang-equipment-conflict")
C_Item.GetSetBonusesForSpecializationByItemID=oldBonuses
local oldInventory=GetInventoryItemID
GetInventoryItemID=function() return secret end; delegated("cobra-fang-equipment-unknown")
GetInventoryItemID=function() error("inventory fault") end; delegated("cobra-fang-equipment-unknown")
GetInventoryItemID=oldInventory
-- Four positive slots suffice despite an unknown fifth; two never do.
equippedPieces=5
C_Item.GetSetBonusesForSpecializationByItemID=function(spec,id)
    if id==270005 then return nil end
    return oldBonuses(spec,id)
end
selected(S.COBRA_SHOT,"cobraSet=4pc")
C_Item.GetSetBonusesForSpecializationByItemID=oldBonuses
equippedPieces=2; delegated("cobra-fang-equipment-conflict")
equippedPieces=4; selected(S.COBRA_SHOT,"cobraSet=4pc")
-- AoE Fang uses the same equipment gate after current Cleave duration.
reset(); enemies=3; known[S.BEAST_CLEAVE_TALENT]=true; auras[S.BEAST_CLEAVE]=true; auraTimes[S.BEAST_CLEAVE]=6
auras[S.NATURES_ALLY]=false; auras[S.COBRA_FANG]=1
selected(S.COBRA_SHOT,"cobraSet=4pc")
equippedPieces=2; delegated("cobra-fang-equipment-conflict")

-- Independent scalar oracle translated directly from the live SimC st / cleave
-- row order (not the production tri-state helpers). Target scoring and terminal
-- no-action are explicit delegation results. Seeded samples are reproducible.
local DELEGATE={}
local function refFull(id)
    local c=charges[id]
    if c.currentCharges==c.maxCharges then return 0 end
    return c.cooldownStartTime+c.cooldownDuration-now+(c.maxCharges-c.currentCharges-1)*c.cooldownDuration
end
local function refReady(id)
    if not known[id] or bindings[id]=="" or not usable[id] then return false end
    if charges[id] then return charges[id].currentCharges>0 end
    return cooldown[id]==0
end
local function refAction()
    local gcd=math.max(.75,1.5/(1+haste/100))
    local cleaveTalent=known[S.BEAST_CLEAVE_TALENT]
    local cleaveRem=auras[S.BEAST_CLEAVE] and auraTimes[S.BEAST_CLEAVE] or 0
    local howl=auras[S.HOWL_OF_THE_PACK_LEADER] or auras[S.HOWL_BOAR] or auras[S.HOWL_BEAR]
    local nature=auras[S.NATURES_ALLY]
    local fang=auras[S.COBRA_FANG] or 0
    local cleaveTable=enemies>2 or cleaveTalent and enemies>1
    if not cleaveTable then
        if refReady(S.BARBED_SHOT) and (cooldown[S.BESTIAL_WRATH]<gcd or refFull(S.BARBED_SHOT)<gcd) then
            -- SimC assumes a usable key binding for the follow-up. Without
            -- that supported setup, only the independent cap proof is owned.
            if bindings[S.BESTIAL_WRATH]=="" and not (refFull(S.BARBED_SHOT)<gcd) then return DELEGATE end
            return enemies==1 and S.BARBED_SHOT or DELEGATE
        end
        if refReady(S.BESTIAL_WRATH) then return S.BESTIAL_WRATH end
        if enemies>1 and refReady(S.WILD_THRASH) then return S.WILD_THRASH end
        local kc=charges[S.KILL_COMMAND]
        local fractional=kc.currentCharges==kc.maxCharges and kc.currentCharges
            or kc.currentCharges+(now-kc.cooldownStartTime)/kc.cooldownDuration
        local howlCD=auras[S.HOWL_COOLDOWN] and auraTimes[S.HOWL_COOLDOWN] or 0
        if refReady(S.KILL_COMMAND) and (howl or
            (cooldown[S.BESTIAL_WRATH]>refFull(S.KILL_COMMAND)+gcd and nature or not known[S.NATURES_ALLY_TALENT])
            and (howlCD>4 or fractional>1.8)) then return S.KILL_COMMAND end
        if refReady(S.COBRA_SHOT) and fang==4 then return S.COBRA_SHOT end
        if refReady(S.BARBED_SHOT) and ((focus<75 or refFull(S.BARBED_SHOT)<gcd)
            and not known[S.SERPENTINE_STRIKES] or known[S.SERPENTINE_STRIKES]) then return S.BARBED_SHOT end
        if refReady(S.COBRA_SHOT) and cooldown[S.BESTIAL_WRATH]>gcd then return S.COBRA_SHOT end
        return DELEGATE
    end
    if refReady(S.WILD_THRASH) and cleaveTalent and
        (bm._Test.context.gcdHistory[1]==S.BESTIAL_WRATH or not auras[S.BEAST_CLEAVE]) then return S.WILD_THRASH end
    if refReady(S.BARBED_SHOT) and refFull(S.BARBED_SHOT)<gcd then return DELEGATE end
    if refReady(S.BESTIAL_WRATH) and (cleaveRem>0 and cooldown[S.WILD_THRASH]<gcd
        or not cleaveTalent or not known[S.WILD_THRASH]) then return S.BESTIAL_WRATH end
    if refReady(S.WILD_THRASH) and not cleaveTalent then return S.WILD_THRASH end
    if refReady(S.KILL_COMMAND) and (nature or known[S.MASTER_HANDLER] and (enemies>3 or howl)
        or not known[S.NATURES_ALLY_TALENT]) and (cleaveRem>gcd*.25 or not cleaveTalent) then return S.KILL_COMMAND end
    if refReady(S.COBRA_SHOT) and fang>0 and cleaveRem>gcd*.25 then return S.COBRA_SHOT end
    if refReady(S.BARBED_SHOT) and (cleaveRem>gcd*.25 or not cleaveTalent) then return DELEGATE end
    if refReady(S.COBRA_SHOT) and (cleaveRem>gcd*.25 or not cleaveTalent) then return S.COBRA_SHOT end
    return DELEGATE
end
local seed=1211017
local function pick(values)
    seed=(seed*16807)%2147483647
    return values[seed%#values+1]
end
local function randomState()
    reset()
    enemies=pick({1,2,3,4,6}); haste=pick({0,13.7,33.3,100,150})
    focus=pick({0,74,75,120})
    for _,id in ipairs({S.BEAST_CLEAVE_TALENT,S.NATURES_ALLY_TALENT,S.MASTER_HANDLER,
        S.SERPENTINE_STRIKES,S.WILD_THRASH}) do known[id]=pick({false,true}) end
    for _,id in ipairs({S.BARBED_SHOT,S.KILL_COMMAND,S.BESTIAL_WRATH,S.WILD_THRASH,S.COBRA_SHOT}) do
        usable[id]=pick({false,true,true,true})
        bindings[id]=pick({"","1","1","1"})
    end
    for _,id in ipairs({S.BARBED_SHOT,S.KILL_COMMAND}) do
        charge(id,pick({0,1,2}),pick({.25,1,1.5,2,5,10}))
    end
    cooldown[S.BESTIAL_WRATH]=pick({0,.5,1.5,6.5,30})
    cooldown[S.WILD_THRASH]=pick({0,1,1.5,5,30})
    auraTimes[S.BEAST_CLEAVE]=pick({0,.2,.375,1,6})
    auras[S.BEAST_CLEAVE]=auraTimes[S.BEAST_CLEAVE]>0
    auraTimes[S.HOWL_COOLDOWN]=pick({0,2,4,8,20})
    auras[S.HOWL_COOLDOWN]=auraTimes[S.HOWL_COOLDOWN]>0
    auras[S.NATURES_ALLY]=pick({false,true})
    auras[S.HOWL_BEAR]=pick({false,true})
    auras[S.COBRA_FANG]=pick({0,1,3,4})
    frame.OnEvent(frame,"UNIT_SPELLCAST_SUCCEEDED","player","oracle-prev",pick({S.BESTIAL_WRATH,S.COBRA_SHOT}))
    raw=pick({{S.COBRA_SHOT,S.KILL_COMMAND,S.BARBED_SHOT},{S.BESTIAL_WRATH,S.BARBED_SHOT,S.KILL_COMMAND},
        {S.WILD_THRASH,S.COBRA_SHOT},{}})
end
local oracleCases=32000
for sample=1,oracleCases do
    randomState()
    local expected=refAction()
    local q=bm.GetQueue()
    local label="oracle seed="..seed.." sample="..sample.." expected="..tostring(expected).." "..bm.GetDecisionTrace()
    if expected==DELEGATE then
        assert(q==raw and bm.GetDecisionTrace():find("fallback=true",1,true),label)
    else
        assert(q[1]==expected and bm.GetDecisionTrace():find("fallback=false",1,true),label)
    end
    assert(bm.GetPreserveQueue()==raw,"oracle M4 isolation")
end
-- Soundness under evidence removal: a self-owned answer with one hidden bit
-- must be the same in BOTH concrete completions, not only the original state.
local partialCases=4000
for sample=1,partialCases do
    randomState()
    local hidden=pick({{auras,S.NATURES_ALLY},{auras,S.HOWL_BEAR},{known,S.MASTER_HANDLER},
        {known,S.NATURES_ALLY_TALENT},{known,S.SERPENTINE_STRIKES}})
    hidden[1][hidden[2]]=false; local no=refAction()
    hidden[1][hidden[2]]=true; local yes=refAction()
    hidden[1][hidden[2]]=secret
    local q=bm.GetQueue()
    if bm.GetDecisionTrace():find("fallback=false",1,true) then
        assert(no~=DELEGATE and yes~=DELEGATE and q[1]==no and q[1]==yes,
            "hidden-bit proof is unsound seed="..seed.." "..bm.GetDecisionTrace())
    else
        assert(q==raw,"hidden-bit fallback must preserve exact current queue")
    end
    assert(bm.GetPreserveQueue()==raw,"hidden-bit M4 isolation")
end
print("BM independent APL oracle passed: "..oracleCases.." states + "..partialCases.." hidden-bit completions")

print("BM 12.1 priority matrix passed: "..count.." decisions + readiness/events/boundaries")
