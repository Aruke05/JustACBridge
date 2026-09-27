dofile("JustACBridge.core/Framework/ActionSequence.lua")
dofile("JustACBridge.core/Framework/ResourcePreparation.lua")
-- Exact three-cooldown resource gate. Pure Lua; no game/process/input access.
local spec, now, rp, maximum, cooldowns, faults, unavailable, overrides, unusable, remaining, cost
local runes, markCost, runeCosts
local secret = {}
function issecretvalue(v) return v == secret end
function GetTime() return now end
JustACBridgePolicyRegistry = {RegisterSpec = function(_, _, v) spec = v end}
local function fault(key, fallback)
    if faults[key] == "throw" then error("injected " .. key) end
    if faults[key] == "missing" then return nil end
    if faults[key] == "secret" then return secret end
    return fallback
end
function GetRuneCooldown(index)
    return 0, 10, fault("runes", index <= runes)
end
function UnitPower() return fault("rp", rp) end
function UnitPowerMax() return fault("maxRP", maximum) end
C_Spell = {
    GetSpellCooldownDuration = function(id, excludeGCD)
        assert(excludeGCD == true)
        return fault("duration", {active = cooldowns[id] == true,
            GetRemainingDuration = function() return fault("remaining", remaining[id]) end})
    end,
    GetSpellPowerCost = function(id)
        if id == 439843 then return fault("markCost", {{type=5,cost=markCost,minCost=markCost}}) end
        if runeCosts[id] ~= nil then
            return fault("runeCost", {{type=5,cost=runeCosts[id],minCost=runeCosts[id]}})
        end
        return fault("cost", {{type = 6, cost = cost, minCost = cost}})
    end,
    IsSpellUsable = function(id)
        local short = id == 1249658 and rp < 60 or id == 439843 and runes < markCost
        return fault("usable", not short and not unusable[id]), fault("noPower", short)
    end,
}
function CreateFrame()
    if faults.frame then error("frame failure") end
    return {
        Hide = function() end,
        SetCooldown = function(self) self.shown = false end,
        SetCooldownFromDurationObject = function(self, duration)
            if faults.setter then error("setter failure") end
            self.shown = duration.active
        end,
        IsShown = function(self) return fault("shown", self.shown) end,
    }
end
local p, context
local raw = {51271, 49143, 439843, 194913, 279302, 49998, 47568, 49020, 49184}
local function reset()
    now, rp, maximum = 100, 42, 100
    cooldowns, faults, unavailable, overrides, unusable = {}, {}, {}, {}, {}
    remaining, cost = {}, 35
    runes, markCost = 6, 2
    runeCosts = {[49020]=2,[49184]=1,[196770]=1,[207230]=1,[43265]=1,[152280]=1,[45524]=1,[343294]=1}
    dofile("JustACBridge.core/Policies/DeathKnight/Frost.lua")
    p = spec.versions[1]
    context = {mode = "lossless", targetGUID = "target-A", now = now,
        resolve = function(id) return overrides[id] or id end,
        canUse = function(id) return not unavailable[id] end,
        inspect = function(id) return {known = not unavailable[id], bound = true} end}
end
local function select(queue)
    context.now = now
    return p.selectLossless(queue or raw, context)
end
local function expect(id, reason)
    local d = assert(select())
    assert(d.spellID == id, tostring(d.spellID) .. " expected " .. tostring(id))
    if reason then assert(d.reason:sub(1, #reason) == reason, d.reason) end
    return d
end
local function held()
    local d = assert(select())
    assert(d.spellID == nil, "unexpected standalone burst " .. tostring(d.spellID))
    local blocked = {[439843]=true,[51271]=true,[1249658]=true,[152279]=true,[279302]=true}
    for _, id in ipairs(d.queue) do
        assert(not blocked[context.resolve(id)], "burst leaked through queue")
    end
    return d
end
local function pool()
    local d = expect(nil)
    assert(d.reason:find("POOL_BREATH:", 1, true) == 1)
    assert(#d.queue == 3 and d.queue[1] == 47568 and d.queue[2] == 49020 and d.queue[3] == 49184)
end
local function success(id)
    p.observePlayerSpellcast("UNIT_SPELLCAST_SUCCEEDED", id, context.targetGUID)
end
reset(); pool()
assert(#raw == 9 and raw[1] == 51271 and raw[2] == 49143)
for _, amount in ipairs({0, 42, 52, 59}) do rp = amount; pool() end
success(47568); pool() -- never infer +40 or release Pillar from an ERW event
for _, amount in ipairs({60, 85, 90, 100}) do rp = amount; expect(439843, "EXPECT_MARK") end
success(439843); cooldowns[439843] = true; expect(51271, "EXPECT_PILLAR")
for _ = 1, 3 do expect(51271) end -- recommendations cannot advance the phase
success(51271); cooldowns[51271] = true; expect(1249658, "EXPECT_BREATH")
rp = 42; pool() -- resource loss after Pillar does not discard the window
rp = 60; expect(1249658)
success(1249658); cooldowns[1249658] = true; expect(279302, "EXPECT_FURY")
success(279302); held()

for _, id in ipairs({51271, 1249658, 279302}) do
    reset(); cooldowns[id] = true; held()
    reset(); unavailable[id] = true; held()
end
reset(); overrides[279302] = 1265384; held()
reset(); overrides[1249658] = 152279; held()
reset(); overrides[111] = 49143
local d = select({111, 49020}); assert(#d.queue == 1 and d.queue[1] == 49020)
reset(); d = select({51271, 49143}); assert(#d.queue == 0)
reset(); d = select({1228433, 49020}); assert(#d.queue == 1 and d.queue[1] == 49020)

-- Both variants require Mark; positive absence is NOT a standalone Pillar license.
reset(); rp = 60; unavailable[439843] = true; expect(nil, "WAIT_MARK:not-learned")
reset(); rp = 60; cooldowns[439843] = true; expect(nil, "WAIT_MARK:cooldown-active")
cooldowns[439843] = false; expect(439843)
reset(); rp = 60; unusable[439843] = true
d = expect(nil, "WAIT_MARK"); assert(#d.queue == 0)
unusable[439843] = nil; expect(439843)

-- Unknown affordability cannot open the burst; unknown cooldowns cannot
-- establish the three-ready premise; ordinary queue order survives WITHOUT burst.
for _, key in ipairs({"usable", "noPower"}) do
    for _, mode in ipairs({"missing", "secret", "throw"}) do
        reset(); rp = 60; faults[key] = mode; expect(nil,"WAIT_FULL_MEMBER:")
    end
end
for _, key in ipairs({"duration", "shown"}) do
    for _, mode in ipairs({"missing", "secret", "throw"}) do
        reset(); faults[key] = mode; held()
        faults[key] = nil; pool()
    end
end
for _, key in ipairs({"frame", "setter"}) do
    reset(); faults[key] = true; held()
end
for _, key in ipairs({"rp", "maxRP"}) do
    for _, mode in ipairs({"missing", "secret", "throw"}) do
        reset(); faults[key] = mode; pool()
        rp = 60; expect(439843) -- exact engine proof, no guessed RP
    end
end
for _, amount in ipairs({-1, 101, math.huge}) do reset(); rp = amount; pool() end
reset(); rp = 0/0; pool()
reset(); maximum = 59; pool()

for _, event in ipairs({"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED"}) do
    reset(); rp = 60; expect(439843)
    p.observePlayerSpellcast(event, 439843, context.targetGUID)
    expect(439843) -- GCD/input failure cannot release the resource gate
end
reset(); rp = 60; expect(439843); success(439843); expect(51271)
success(51271); cooldowns[51271] = true; now = 110; held()
reset(); rp = 60; expect(439843); success(439843); now = 99; held()
reset(); rp = 60; expect(439843); success(439843); expect(51271)
success(51271); cooldowns[51271] = true
context.targetGUID = "target-B"; held()
context.targetGUID = "target-A"; held()
reset(); rp = 60; expect(439843); success(439843); expect(51271)
success(51271); cooldowns[51271] = true
p.resetLosslessSelection(); held()
reset(); context.outOfRange = true; held()
reset(); context.targetGUID = nil; held()

-- CD/resource updates may precede success events; keep the short proposal
-- receipt, but never infer a successful cast from those updates.
reset(); rp = 60; expect(439843); success(439843); expect(51271)
cooldowns[51271] = true; expect(nil, "WAIT_PILLAR")
success(51271); expect(1249658); success(152279); expect(279302)
reset(); rp = 60; expect(439843); rp = 42; pool()
success(439843); rp = 60; expect(51271)
reset(); rp = 60; expect(439843); cooldowns[439843] = true
expect(nil, "WAIT_CAST_CONFIRM"); success(439843); expect(51271)
success(51271); expect(1249658); cooldowns[1249658] = true
expect(nil, "WAIT_BREATH_CONFIRM"); success(1249658); expect(279302)
reset(); p.observePlayerSpellcast("UNIT_SPELLCAST_SUCCEEDED", nil, "target-A"); pool()

-- Pre-pool only for an actually imminent joint window, not each Breath CD.
local function upcoming(seconds)
    reset()
    for _, id in ipairs({51271,1249658,279302}) do cooldowns[id],remaining[id]=true,seconds end
end
for _, seconds in ipairs({0.001,2,5,5.999999}) do
    upcoming(seconds)
    d=expect(nil,seconds<=0.75 and "POOL_BREATH:" or "PREP_BREATH_WITHIN_6S:")
    assert(#d.queue==3 and d.queue[1]==47568 and d.queue[2]==49020 and d.queue[3]==49184)
    assert(select({49143,51271,439843,279302}).queue[1]==nil)
    rp=60
    if seconds<=0.75 then expect(439843) -- even hidden haste proves the minimum GCD
    else expect(nil,"PREP_BREATH_WITHIN_6S:") end
    cooldowns={}; expect(439843,"EXPECT_MARK")
    success(439843); expect(51271); success(51271); expect(1249658)
    success(1249658); expect(279302)
end
for _, seconds in ipairs({18.000001,19,35,90}) do
    upcoming(seconds); local waiting=expect(nil,"WAIT_SMALL_PILLAR"); assert(waiting.queue[1]==49143)
end
for _, id in ipairs({51271,1249658,279302}) do
    upcoming(2); remaining[id]=35; held()
    upcoming(2); remaining[id]=nil; held()
    upcoming(2); unavailable[id]=true; held()
end
upcoming(2); cooldowns[279302]=false; expect(nil,"PREP_BREATH_WITHIN_6S:")
upcoming(2); cooldowns[51271]=false; remaining[1249658]=35; held()
for _, amount in ipairs({42,52,59,60,85,90,94.999,95,100}) do
    upcoming(2); rp=amount
    d=select({49143,49020,49184})
    assert(d.queue[1]==(amount>=95 and 49143 or 49020))
end
upcoming(2); rp=85; cost=25; assert(select({49143,49020}).queue[1]==49143)
cost=35; assert(select({49143,49020}).queue[1]==49020) -- fresh cost, not cached
maximum=130; rp=100; assert(select({49143,49020}).queue[1]==49143)
rp=59; assert(select({49143,49020}).queue[1]==49020) -- fresh resource, no latch
for _, key in ipairs({"cost","rp","maxRP"}) do
    for _, mode in ipairs({"missing","secret","throw"}) do
        upcoming(2); rp=100; faults[key]=mode
        assert(select({49143,49020}).queue[1]==49020)
    end
end
for _, mode in ipairs({"missing","secret","throw"}) do
    upcoming(2); faults.remaining=mode; held()
end
upcoming(2); cooldowns[439843]=true; remaining[439843]=35; held()
remaining[439843]=2; expect(nil,"PREP_BREATH_WITHIN_6S:")
upcoming(2); unavailable[439843]=true; held()
upcoming(2); context.inspect=function() return {known=secret,bound=true} end; held()
upcoming(2); overrides[279302]=1265384; held()
upcoming(2); context.outOfRange=true; held()
upcoming(2); context.targetGUID=nil; held()
upcoming(2); expect(nil,"PREP_BREATH_WITHIN_6S:"); p.resetLosslessSelection()
remaining[1249658]=35; held() -- resets / CD changes cannot keep stale prep
-- Both dragons FAR: wait for Mark + Pillar, with no Breath RP gate.
local function smallWindow()
    reset()
    cooldowns[1249658], cooldowns[279302] = true, true
    remaining[1249658], remaining[279302] = 35, 35
end
for _, amount in ipairs({0,42,59,60,100}) do
    smallWindow(); rp=amount
    expect(439843,"SMALL_EXPECT_MARK")
    for _=1,3 do expect(439843) end
    p.observePlayerSpellcast("UNIT_SPELLCAST_FAILED",439843,context.targetGUID)
    expect(439843)
    success(439843); cooldowns[439843]=true
    expect(51271,"SMALL_EXPECT_PILLAR"); success(51271)
    expect(nil,"SMALL_COMPLETE_WAIT_COOLDOWN")
    cooldowns[51271]=true
    d=expect(nil,"WAIT_SMALL_PILLAR"); assert(d.queue[1]==49143)
end
smallWindow(); cooldowns[439843]=true
d=expect(nil,"WAIT_SMALL_MARK:cooldown-active"); assert(d.queue[1]==49143)
cooldowns[439843]=false; cooldowns[51271]=true
d=expect(nil,"WAIT_SMALL_PILLAR"); assert(d.queue[1]==49143)
cooldowns[51271]=false; expect(439843)
-- Original queue can omit Mark entirely or be empty; no downstream bypass.
smallWindow(); d=select({51271,49143}); assert(d.spellID==439843)
d=select({}); assert(d.spellID==439843)
cooldowns[439843]=true
expect(nil,"WAIT_SMALL_CAST_CONFIRM"); success(439843); expect(51271)
cooldowns[51271]=true; expect(nil,"WAIT_SMALL_CAST_CONFIRM")
success(51271); expect(nil,"WAIT_SMALL_PILLAR")
-- Near / unknown / only one dragon far must NOT trigger this new branch.
for _, id in ipairs({1249658,279302}) do
    for _, value in ipairs({2,5.9999}) do
        smallWindow(); remaining[id]=value; held()
    end
    smallWindow(); remaining[id]=nil; held()
    smallWindow(); cooldowns[id]=false; held()
end
smallWindow(); remaining[1249658],remaining[279302]=18,18; held()
smallWindow(); unavailable[439843]=true; expect(nil,"WAIT_SMALL_MARK:not-learned")
for _, evidence in ipairs({{known=true,bound=nil},{known=nil,bound=true},{known=secret,bound=true}}) do
    smallWindow(); context.inspect=function() return evidence end
    d=expect(nil,"WAIT_SMALL_MARK"); assert(d.queue[1]==49143)
end
smallWindow(); unusable[439843]=true; assert(#expect(nil,"WAIT_SMALL_MARK").queue==0)
unusable[439843]=nil; expect(439843); success(439843)
-- Small pair already committed is completed without inventing a Breath step.
cooldowns[1249658],cooldowns[279302]=false,false; rp=0; expect(51271)
success(51271); cooldowns[51271]=true; held()
smallWindow(); expect(439843); success(439843); cooldowns[439843]=true
context.targetGUID="B"; expect(nil,"WAIT_SMALL_MARK")
context.targetGUID="target-A"; expect(nil,"WAIT_SMALL_MARK")
smallWindow(); expect(439843); success(439843); cooldowns[439843]=true
now=110; expect(nil,"SMALL_SEQUENCE_EXPIRED"); expect(nil,"WAIT_SMALL_MARK")
smallWindow(); expect(439843); success(439843); cooldowns[439843]=true
now=110; context.targetContext={evidence="test-unknown"}
expect(nil,"WAIT_TARGET_EVIDENCE"); context.targetContext=nil; expect(nil,"WAIT_SMALL_MARK")
smallWindow(); expect(439843); success(439843); cooldowns[439843]=true
p.resetLosslessSelection(); expect(nil,"WAIT_SMALL_MARK")
-- Completed small window cannot prevent the next full 60-RP four-step window.
smallWindow(); expect(439843); success(439843); expect(51271); success(51271)
cooldowns[51271]=true; expect(nil,"WAIT_SMALL_PILLAR")
cooldowns={}; rp=42; pool(); rp=60; expect(439843,"EXPECT_MARK")
success(439843); expect(51271); success(51271); expect(1249658); success(1249658); expect(279302)
reset(); rp=42; unavailable[439843]=true
assert(expect(nil,"WAIT_MARK:not-learned").queue[1]==49143)
-- User contract: ONLY the two complete shapes, never A + one dragon.
-- Every source position is adversarial; missing/empty original queue is not
-- permission to skip Mark, and exactly 18 seconds belongs to the WAIT side.
local states = {0,2,6,17.999999,18,18 + 2^-48,19,35,"unknown"}
local matrixCases = 0
for _, breath in ipairs(states) do
    for _, fury in ipairs(states) do
        for _, amount in ipairs({0,42,59,60,95}) do
            for _, pillarCD in ipairs({false,true}) do
                reset(); rp=amount
                cooldowns[51271]=pillarCD; remaining[51271]=pillarCD and 35 or 0
                for id, value in pairs({[1249658]=breath,[279302]=fury}) do
                    cooldowns[id]=value~=0
                    remaining[id]=type(value)=="number" and value or nil
                end
                local full=breath==0 and fury==0
                local small=type(breath)=="number" and type(fury)=="number" and breath>18 and fury>18
                local expected=not pillarCD and (small or full and amount>=60)
                local q={279302,1249658,51271,439843,49143,49020,49184}
                local decision=select(q)
                if expected then
                    assert(decision.spellID==439843)
                    assert(decision.reason:find(small and "SMALL_EXPECT_MARK" or "EXPECT_MARK",1,true)==1)
                else
                    assert(decision.spellID==nil)
                    for _, id in ipairs(decision.queue) do assert(id==49143 or id==49020 or id==49184) end
                    assert(decision.queue[#decision.queue]==49184)
                end
                assert(q[1]==279302 and #q==7)
                matrixCases=matrixCases+1
            end
        end
    end
end
assert(matrixCases==810)
-- 18 s alignment waits do NOT mean 18 s resource pooling; all members must
-- be within the independent 6 s horizon. One ready + one long always waits.
for _, pair in ipairs({{0,35},{35,0},{18,18},{2,18},{35,18},{18,35}}) do
    reset(); rp=42
    cooldowns[1249658],cooldowns[279302]=pair[1]>0,pair[2]>0
    remaining[1249658],remaining[279302]=pair[1],pair[2]
    d=select({51271,279302,1249658,439843,49143,49020})
    assert(d.spellID==nil and d.queue[1]==49143 and d.queue[2]==49020)
    d=select({51271,279302,1249658,439843}); assert(#d.queue==0)
end
-- An uncommitted recommendation cannot lock a small group after live CD
-- evidence changes; committed Mark CAN finish only its original small pair.
smallWindow(); rp=60; expect(439843,"SMALL_EXPECT_MARK")
remaining[1249658]=18; held()
cooldowns={}; expect(439843,"EXPECT_MARK"); success(439843); expect(51271)
success(51271); expect(1249658); success(1249658); expect(279302)
-- A downstream member currently unusable must stop the whole opener.
for _, id in ipairs({51271,279302}) do
    reset(); rp=60; unusable[id]=true
    expect(nil,"WAIT_FULL_MEMBER:")
    unusable[id]=nil; expect(439843)
end
-- No success receipt: manual Pillar/aura/CD observations cannot start at B.
reset(); rp=60; success(51271); cooldowns[51271]=true; held()
-- Recall is an explicit separate action, but does not exempt other members.
reset(); overrides[279302]=1265384
local recall=select({51271,1249658,439843,279302,49143})
assert(#recall.queue==2 and recall.queue[1]==279302 and recall.queue[2]==49143)
-- Mark uses runes, independently of Breath's RP. Prepare ONLY when the
-- actual chosen group is near. Test both asymmetric pair cooldowns as well.
local function markUpcoming(markSeconds,pillarSeconds)
    smallWindow(); runes=2
    cooldowns[439843],cooldowns[51271]=markSeconds>0,pillarSeconds>0
    remaining[439843],remaining[51271]=markSeconds,pillarSeconds
end
local runeQueue={49020,49184,49143,47568,51271,439843}
for _, pair in ipairs({{2,2},{0,2},{2,0},{5.999999,0}}) do
    markUpcoming(pair[1],pair[2])
    d=select(runeQueue); assert(d.queue[1]==49143 and d.queue[2]==47568 and #d.queue==2)
    assert(d.reason:find("PREP_MARK_WITHIN_6S:reserve=2",1,true))
    runes=3; d=select(runeQueue); assert(d.queue[1]==49184)
    runes=4; d=select(runeQueue); assert(d.queue[1]==49020)
    runes=6; d=select(runeQueue); assert(d.queue[1]==49020)
end
for _, pair in ipairs({{6,0},{0,6},{35,2},{2,35}}) do
    markUpcoming(pair[1],pair[2]); d=select(runeQueue)
    assert(d.queue[1]==49020 and not d.reason:find("PREP_MARK_WITHIN_6S",1,true))
end
-- Dynamic Mark/candidate costs, including free Howling Blast; no proc guess.
markUpcoming(2,2); runes=3; markCost=3
assert(select(runeQueue).queue[1]==49143)
markCost=1; assert(select(runeQueue).queue[1]==49020)
runeCosts[49020]=3; assert(select(runeQueue).queue[1]==49184)
markCost=2; runes=0; runeCosts[49184]=0
assert(select(runeQueue).queue[1]==49184)
for _, key in ipairs({"runes","markCost","runeCost"}) do
    for _, mode in ipairs({"missing","secret","throw"}) do
        markUpcoming(2,2); faults[key]=mode
        d=select(runeQueue); assert(d.queue[1]==49143 and d.queue[2]==47568)
    end
end
markUpcoming(2,2); faults.runes="secret"; runeCosts[49184]=0
assert(select(runeQueue).queue[1]==49184)
-- Already ready but missing Mark resources no longer pauses all M5. Safe
-- RP spending/recovery remains original-order; RP gains are never inferred.
smallWindow(); runes=1; rp=0
assert(select(runeQueue).queue[1]==49143)
success(47568); assert(select(runeQueue).queue[1]==49143)
runes=2; expect(439843); success(439843); runes=0; expect(51271)
-- Full near-window simultaneously preserves 60 RP and Mark's CURRENT runes.
upcoming(2); runes=2; rp=42
assert(select({49020,49143,49184,47568}).queue[1]==47568)
runes=4; assert(select({49020,49143,49184,47568}).queue[1]==49020)
runes=2; rp=95; assert(select({49020,49143,49184,47568}).queue[1]==49143)
rp=94.999; assert(select({49020,49143,49184,47568}).queue[1]==47568)
-- Full group ready: low runes must not spend the already saved 60 RP.
reset(); runes=1; rp=60
assert(select({49020,49143,49184,47568}).queue[1]==47568)
rp=95; assert(select({49020,49143,49184,47568}).queue[1]==49143)
rp=60; runeCosts[49184]=0; assert(select({49020,49143,49184,47568}).queue[1]==49184)
runes=2; expect(439843); success(439843); runes=0; expect(51271)
success(51271); expect(1249658); success(1249658); expect(279302)
-- A near pair with an 18s/unknown/only-one-long dragon does not justify
-- holding runes now: that group is not actually entering its 6s window.
for _, value in ipairs({6,18,35}) do
    reset(); runes=0; rp=42; cooldowns[1249658]=true; remaining[1249658]=value
    assert(select(runeQueue).queue[1]==49020)
end
markUpcoming(2,2); remaining[279302]=nil; assert(select(runeQueue).queue[1]==49020)
markUpcoming(2,2); unavailable[439843]=true; assert(select(runeQueue).queue[1]==49020)
markUpcoming(2,2); overrides[279302]=1265384; assert(select(runeQueue).queue[1]==49020)
-- Empty filtered results, fresh CD/resource after reset, transformed spender.
markUpcoming(2,2); assert(#select({49020,49184,51271}).queue==0)
markUpcoming(2,2); overrides[111]=49020
assert(select({111,47568}).queue[1]==47568)
markUpcoming(2,2); p.resetLosslessSelection(); remaining[51271]=35
assert(select(runeQueue).queue[1]==49020)
markUpcoming(2,2); runes=6; runeCosts[49020]=1.5
assert(select({49020,47568}).queue[1]==47568) -- fractional rune cost is not a supported proof
markCost=1.5; runeCosts[49020]=2
assert(select({49020,47568}).queue[1]==47568)
-- Staggered cooldown regression: opener now, successors by their execution
-- deadline. The same public sequence engine handles small and full groups.
do
    local originalHaste=GetHaste
    local haste=50
    GetHaste=function() return fault("haste",haste) end
    local function timed(small,seconds)
        if small then smallWindow() else reset(); rp=60 end
        cooldowns[51271],remaining[51271]=true,seconds
        if not small then
            cooldowns[1249658],remaining[1249658]=true,seconds
            cooldowns[279302],remaining[279302]=true,seconds
        end
    end
    for _, small in ipairs({true,false}) do
        for _, h in ipairs({0,25,50,100,200}) do
            haste=h; local gcd=math.max(0.75,1.5/(1+h/100))
            for _, delta in ipairs({-0.001,0,0.001}) do
                timed(small,gcd+delta)
                if delta<=0 then
                    d=expect(439843)
                    assert(d.reason:find("START_TIMING:",1,true))
                    -- A failed key/GCD never advances; a success always does.
                    p.observePlayerSpellcast("UNIT_SPELLCAST_FAILED",439843,context.targetGUID)
                    expect(439843)
                    success(439843); cooldowns[439843],remaining[439843]=true,45
                    d=held(); assert(#d.queue==0) -- no filler GCD steals the handoff
                    now=now+gcd
                    cooldowns[51271]=false
                    expect(51271); success(51271); cooldowns[51271]=true
                    if not small then
                        -- Successors may still be cooling on an early frame;
                        -- this is WAIT, never 'unexpected CD' cancellation.
                        d=held(); assert(#d.queue==0 and d.reason=="WAIT_BREATH_STEP")
                        cooldowns[1249658]=false
                        expect(1249658); success(1249658); cooldowns[1249658]=true; rp=0
                        d=held(); assert(#d.queue==0 and d.reason=="WAIT_FURY")
                        cooldowns[279302]=false; expect(279302); success(279302)
                    end
                else
                    held() -- a genuinely late successor cannot start the opener
                end
            end
        end
    end
    haste=50
    -- No double-counting off-GCD buttons, even if just the LAST CD is late.
    for _, id in ipairs({51271,1249658,279302}) do
        reset(); rp=60; cooldowns[id],remaining[id]=true,1.01; held()
        remaining[id]=1; expect(439843)
    end
    -- Mark itself must be affordable/ready now; no predicted rune/RP gains.
    timed(false,1); cooldowns[439843],remaining[439843]=true,0.01; held()
    timed(false,1); rp=59; held(); rp=60; expect(439843)
    timed(false,1); runes=1; held(); runes=2; expect(439843)
    timed(true,1); runes=1; held(); runes=2; rp=0; expect(439843)
    for _, key in ipairs({"haste","remaining"}) do
        for _, mode in ipairs({"missing","secret","throw"}) do
            timed(false,1); faults[key]=mode; held()
            remaining[51271],remaining[1249658],remaining[279302]=0.7,0.7,0.7
            if key=="haste" then expect(439843) else held() end
            cooldowns={}; expect(439843) -- unknown optimization cannot block all-ready
        end
    end
    -- Current haste is never sticky. Loss of a proposal without success does
    -- not count as commitment, and a shorter next GCD re-evaluates the budget.
    timed(false,1.2); haste=0; expect(439843)
    haste=100; held(); haste=0; expect(439843)
    context.targetGUID="new-target"; cooldowns[439843]=true; held()
    context.targetGUID="target-A"; held()
    -- Five natural cycles, no reset between them: large/small/large/small/large.
    -- Each later Pillar comes off CD one GCD AFTER Mark, with no accumulated
    -- waiting drift. Arrival times are derived from the actual successes.
    for _, h in ipairs({0,25,50,75,100}) do
        reset(); haste=h; rp=60
        local gcd=math.max(0.75,1.5/(1+h/100))
        local ends={}; local start=100
        local function tick(t)
            now=t
            for _,id in ipairs({439843,51271,1249658,279302}) do
                remaining[id]=math.max(0,(ends[id] or 0)-now)
                cooldowns[id]=remaining[id]>0
            end
        end
        local function cast(id,duration)
            expect(id); success(id); ends[id]=now+duration; tick(now)
        end
        for round=0,4 do
            tick(start+45*round); rp=60; runes=6
            local large=round%2==0
            local opening=expect(439843)
            assert(opening.reason:find(large and "EXPECT_MARK:" or "SMALL_EXPECT_MARK:",1,true)==1)
            cast(439843,45)
            -- Actual casting still requires the engine to end the cooldown;
            -- previous floating-point endpoint additions may differ by one ULP.
            tick(math.max(start+45*round+gcd,ends[51271] or 0,
                large and (ends[1249658] or 0) or 0,large and (ends[279302] or 0) or 0))
            cast(51271,45)
            if large then cast(1249658,90); rp=0; cast(279302,90) end
        end
    end
    GetHaste=originalHaste
end
do
    reset(); rp=42; runes=1
    local q={51271,49143,49020,439843,1249658,279302}
    context.mode="preserve"
    local decision=select(q)
    assert(decision.spellID==nil and #decision.queue==2)
    assert(decision.queue[1]==49143 and decision.queue[2]==49020)
    assert(decision.reason=="BURST_PREPARATION_DISABLED_FOR_MODE")
    context.mode=nil; assert(select(q).queue[1]==49143)
    context.mode="lossless"; rp=60; runes=2; expect(439843)
    context.mode="preserve"; assert(select(q).queue[1]==49143)
    context.mode="lossless"; success(439843); expect(51271) -- M4 read cannot clear the M5 receipt
end
print("frost preparation tests passed")
