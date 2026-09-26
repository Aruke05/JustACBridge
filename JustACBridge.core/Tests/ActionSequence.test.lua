-- Framework contract: artificial IDs, no class-specific APL or game runtime.
dofile("JustACBridge.core/Framework/ActionSequence.lua")
local S = JustACBridgeActionSequence
local secret = {}
function issecretvalue(v) return v == secret end
local function yes() return true end
local function no() return false end
local function unknown() return nil end
local function hidden() return secret end
local function throws() error("unavailable API") end
assert(S.Ownership({1}, {yes, no}) == true)
assert(S.Ownership({1}, {no, yes}) == true)
assert(S.Ownership({1}, {no, no}) == false)
assert(S.Ownership({1}, {no, false}) == false)
for _, f in ipairs({unknown, hidden, throws}) do
    assert(S.Ownership({1}, {f, no}) == nil)
    assert(S.Ownership({1}, {f, yes}) == true)
end
assert(S.Ownership({1}, {false, false}) == nil)
assert(S.Ownership({1, 2}, {function(id) return id == 2 end}) == true)
assert(S.Binding(true, "C5") == true)
assert(S.Binding(true, "") == false)
assert(S.Binding(true, nil) == nil)
assert(S.Binding(true, secret) == nil)
assert(S.Binding(false, "C5") == nil)

local function evidence() return {known = true, bound = true, ready = true, usable = true, noPower = false} end
assert(S.Prerequisite(evidence()) == "ready")
for _, key in ipairs({"known", "bound", "ready", "usable", "noPower"}) do
    local e = evidence(); e[key] = nil; assert(S.Prerequisite(e) == "wait", key)
    e[key] = secret; assert(S.Prerequisite(e) == "wait", key)
end
for _, key in ipairs({"known", "bound"}) do
    local e = evidence(); e[key] = false; assert(S.Prerequisite(e) == "skip", key)
end
for _, key in ipairs({"ready", "usable"}) do
    local e = evidence(); e[key] = false; assert(S.Prerequisite(e) == "wait", key)
end
local e = evidence(); e.noPower = true; assert(S.Prerequisite(e) == "wait")
assert(S.Describe({known=secret}):find("known=unknown", 1, true))

local config = {withinSeconds=10, cancelOnFailure=false, cancelSpellIDs={[99]=true},
    steps={{spellID=10,name="PRE",optional=true}, {spellID=20,name="MAIN",windowAnchor=true},
        {spellID=30,name="FOLLOW",aliases={31}}, {spellID=40,name="END"}}}
local function context(now, guid) return {now=now or 100, targetGUID=guid or "A"} end
local s = S.New(config)
assert(s:Check(context()))
assert(s:Propose(1, context()).spellID == 10)
for _=1,5 do s:Propose(1, context()) end
assert(s.step == nil) -- recommendation is NOT successful execution
s:Observe("UNIT_SPELLCAST_SUCCEEDED", 999, "A", 100); assert(s.step == nil)
s:Observe("UNIT_SPELLCAST_FAILED", 10, "A", 100); assert(not s.suspended)
s:Observe("UNIT_SPELLCAST_SUCCEEDED", 10, "A", 100); assert(s.step == 2)
s:Propose(2,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",20,"A",100)
assert(s.step == 3 and s.windowAt == 100)
s:Propose(3,context(102)); s:Observe("UNIT_SPELLCAST_SUCCEEDED",31,"A",102)
assert(s.step == 4)
s:Propose(4,context(103)); s:Observe("UNIT_SPELLCAST_SUCCEEDED",40,"A",103)
assert(s.suspended and s.step == nil)

-- Target invalidation and proposal expiry cannot revive historical order.
for _, invalid in ipairs({"different-target", "out-of-range", "no-target", "expired", "rewind"}) do
    s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",10,"A",100)
    local c=context()
    if invalid=="different-target" then c.targetGUID="B"
    elseif invalid=="out-of-range" then c.outOfRange=true
    elseif invalid=="no-target" then c.targetGUID=nil
    elseif invalid=="expired" then c.now=110
    else c.now=99 end
    s:Check(c); assert(s.step == nil, invalid)
    s:Check(context()); assert(s.step == nil, invalid)
end
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",10,"A",110)
assert(s.suspended and s.step == nil)
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",20,"A",100)
assert(s.suspended) -- real out-of-order success cancels
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",99,"A",100)
assert(s.suspended)
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",secret,"A",100)
assert(s.step == nil and not s.suspended)
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",10,"B",100)
assert(s.target == nil and s.step == nil)
-- Absolute anchor expiry wins even when individual steps are more recent.
s=S.New(config); s:Propose(1,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",10,"A",100)
s:Propose(2,context()); s:Observe("UNIT_SPELLCAST_SUCCEEDED",20,"A",100)
s:Propose(3,context(108)); s:Observe("UNIT_SPELLCAST_SUCCEEDED",30,"A",108)
assert(not s:Check(context(110)))
-- A future caller cannot accidentally reintroduce "not ready => skip" by
-- proposing the downstream action directly. Optional steps need explicit proof.
s=S.New(config)
assert(not pcall(s.Propose,s,2,context()))
local cooling = evidence(); cooling.ready = false
assert(not pcall(s.Propose,s,2,context(),nil,{[1]=cooling}))
assert(not pcall(s.Propose,s,2,context(),nil,{[1]={known=nil}}))
assert(s:Propose(2,context(),nil,{[1]={known=false}}).spellID==20)
assert(not pcall(s.Propose,s,3,context(),nil,{[1]={known=false},[2]={known=false}}))
s:Observe("UNIT_SPELLCAST_SUCCEEDED",20,"A",100)
assert(not pcall(s.Propose,s,1,context()))
-- Separate configurations/instances are isolated (future class opt-ins).
local t=S.New({withinSeconds=2,cancelOnFailure=true,
    steps={{spellID=101,name="A"},{spellID=102,name="B"}}})
t:Propose(1,context()); t:Observe("UNIT_SPELLCAST_FAILED",101,"A",100)
assert(t.suspended)
s=S.New(config); s:Propose(1,context()); assert(not s.suspended)
s:Reset(); assert(not s:HasProposal(100) and s.target == nil)
local raw={20,5,30,6,10,-77}
local r=S.Filter(raw,function(id) return id==30 and 40 or id end,{[20]=true,[40]=true,[10]=true},"WAIT")
assert(#r.queue==3 and r.queue[1]==5 and r.queue[2]==6 and r.queue[3]==-77)
assert(#raw==6 and raw[1]==20)
assert(#S.Filter({20},function(id)return id end,{[20]=true},"WAIT").queue==0)
local recall=S.Filter({20,30,5},function(id) return id==20 and 126 or id end,
    {[20]=true,[30]=true},"WAIT",{[126]=true})
assert(#recall.queue==2 and recall.queue[1]==20 and recall.queue[2]==5)
-- The actual manifest, not just test setup, must load this dependency first.
local file=assert(io.open("JustACBridge.core/JustACBridge.toc","r"))
local toc=file:read("*a"); file:close()
local framework=assert(toc:find("Framework\\ActionSequence.lua",1,true))
assert(framework < assert(toc:find("Policies\\DeathKnight\\Frost.lua",1,true)))
assert(framework < assert(toc:find("\nJustACBridge.lua",1,true)))
print("action sequence framework tests passed")
