-- Native API contract mocks + opaque secret fault injection; never touch WoW.
local opaque = setmetatable({}, {
    __lt = function() error("secret compared") end,
    __le = function() error("secret compared") end,
    __add = function() error("secret arithmetic") end,
    __sub = function() error("secret arithmetic") end,
    __div = function() error("secret arithmetic") end,
    __tostring = function() error("secret logged") end,
})
function issecretvalue(v) return rawequal(v, opaque) end
local remaining, amount, maximum, hiddenCD, hiddenRP, hiddenResult, resultBit
local curveMode, durationMode, resultMode, costRows
local evaluations, lastIgnoreGCD = 0, nil
Enum = {LuaCurveType = {Step = 1}}
C_CurveUtil = {CreateCurve = function()
    if curveMode == "throw" then error("curve failed") end
    local c = {points = {}}
    function c:SetType(t) assert(t == 1) end
    function c:AddPoint(x,y) self.points[#self.points+1] = {x,y} end
    function c:Evaluate(x)
        if curveMode == "wrong-boundary" then
            return x > self.points[2][1] and 100 or 0
        elseif curveMode == "linear" then return x * 100
        elseif curveMode == "secret" then return opaque end
        local y = self.points[1][2]
        for _, p in ipairs(self.points) do if x >= p[1] then y = p[2] end end
        return y
    end
    return c
end}
local function evaluated(curve, x)
    evaluations = evaluations + 1
    local value = curve:Evaluate(x)
    if resultMode == "throw" then error("engine failed") end
    if resultMode == "nil" then return nil end
    if resultMode == "invalid" then return 37 end
    resultBit = value == 100
    return hiddenResult and opaque or value
end
C_Spell = {
    GetSpellCooldownDuration = function(_, ignoreGCD)
        lastIgnoreGCD = ignoreGCD
        if durationMode == "throw" then error("duration failed") end
        if durationMode == "nil" then return nil end
        if durationMode == "secret" then return opaque end
        return {
            GetRemainingDuration = function() return hiddenCD and opaque or remaining end,
            EvaluateRemainingDuration = function(_, curve) return evaluated(curve, remaining) end,
        }
    end,
    GetSpellPowerCost = function()
        if costRows == "throw" then error("cost failed") end
        return costRows
    end,
}
function UnitPower() return hiddenRP and opaque or amount end
function UnitPowerMax() return maximum end
function UnitPowerPercent(_, pt, unmodified, curve)
    assert(pt == 6 or pt == 0); assert(unmodified == false)
    return evaluated(curve, amount / maximum)
end
local function query(name, value)
    assert(name == "ReadBinaryPredicate" and rawequal(value, opaque))
    return true, resultBit
end
local P
local function reset()
    remaining, amount, maximum = 5, 42, 100
    hiddenCD, hiddenRP, hiddenResult = false, false, false
    curveMode, durationMode, resultMode = nil, nil, nil
    costRows = {{type=6,cost=35,minCost=35,costPercent=0,costPerSec=0,requiredAuraID=0}}
    evaluations = 0
    dofile("JustACBridge.core/Framework/ResourcePreparation.lua")
    P = JustACBridgeResourcePreparation
end
for _, hidden in ipairs({false,true}) do
    reset(); hiddenCD, hiddenRP, hiddenResult = hidden, hidden, hidden
    for _, time in ipairs({0,2,5.999999,6,6.000001,8,35,90,4000}) do
        remaining = time
        assert(P.CooldownBelow(101,6,query) == (time < 6))
        assert(lastIgnoreGCD == true)
    end
    for _, max in ipairs({100,125,130}) do
        maximum = max
        for _, value in ipairs({0,42,59.9999,60,60.0001,85,90,95,100}) do
            amount = value
            for _, threshold in ipairs({0,60,85,95,100,max,max+1}) do
                assert(P.ResourceAtLeast("player",6,threshold,query) == (value >= threshold))
            end
        end
    end
end
-- No cached answers: fresh readings at the same time, including secret frames.
reset(); assert(P.ResourceAtLeast("player",6,60,query) == false)
amount=95; hiddenRP=true; hiddenResult=true
assert(P.ResourceAtLeast("player",6,95,query) == true)
amount=94.999; assert(P.ResourceAtLeast("player",6,95,query) == false)
remaining=5; hiddenCD=true; assert(P.CooldownBelow(101,6,query) == true)
remaining=35; assert(P.CooldownBelow(101,6,query) == false)

for _, mode in ipairs({"throw","nil","secret"}) do
    reset(); durationMode=mode; assert(P.CooldownBelow(101,6,query) == nil)
end
for _, mode in ipairs({"throw","wrong-boundary","linear","secret"}) do
    reset(); hiddenCD=true; hiddenRP=true; curveMode=mode
    assert(P.CooldownBelow(101,6,query) == nil)
    assert(P.ResourceAtLeast("player",6,60,query) == nil)
    assert(evaluations == 0) -- failed native curve self-test never reaches engine
end
for _, mode in ipairs({"throw","nil","invalid"}) do
    reset(); hiddenCD=true; hiddenRP=true; resultMode=mode
    assert(P.CooldownBelow(101,6,query) == nil)
    assert(P.ResourceAtLeast("player",6,60,query) == nil)
end
for _, callback in ipairs({
    function() return true,nil end, function() return true,opaque end,
    function() return false,true end, function() error("adapter failure") end,
}) do
    reset(); hiddenCD=true; hiddenRP=true; hiddenResult=true
    assert(P.CooldownBelow(101,6,callback) == nil)
    assert(P.ResourceAtLeast("player",6,60,callback) == nil)
end
reset(); hiddenCD=true; hiddenResult=true; assert(P.CooldownBelow(101,6) == nil)
reset(); hiddenRP=true; maximum=opaque; assert(P.ResourceAtLeast("player",6,60,query) == nil)
for _, value in ipairs({-1,math.huge,0/0}) do
    reset(); amount=value; assert(P.ResourceAtLeast("player",6,60,query) == nil)
    remaining=value; assert(P.CooldownBelow(101,6,query) == nil)
end
reset(); amount=101; assert(P.ResourceAtLeast("player",6,60,query) == nil)

reset(); assert(P.FixedCost(201,6) == 35)
for _, value in ipairs({0,25,35,40}) do
    costRows={{type=6,cost=value,minCost=value}}
    assert(P.FixedCost(201,6) == value)
end
for _, key in ipairs({"cost","minCost","type","costPercent","costPerSec","requiredAuraID"}) do
    for _, value in ipairs({opaque,-1,math.huge,0/0}) do
        reset(); costRows[1][key]=value; assert(P.FixedCost(201,6) == nil)
    end
end
for _, row in ipairs({{type=6,cost=35,minCost=10}, {type=6,cost=35,costPercent=10},
    {type=6,cost=35,costPerSec=5}, {type=6,cost=35,requiredAuraID=123}}) do
    reset(); costRows={row}; assert(P.FixedCost(201,6) == nil)
end
for _, rows in ipairs({{},opaque,"throw",{{type=0,cost=20}}}) do
    reset(); costRows=rows; assert(P.FixedCost(201,6) == nil)
end
reset(); costRows=nil; assert(P.FixedCost(201,6) == nil)
reset(); costRows={{type=6,cost=25},{type=6,cost=10},{type=0,cost=20}}
assert(P.FixedCost(201,6) == 35)

-- Two explicitly configured policies share primitives, never a pooling latch.
reset()
local config={blocked={[101]=true},spenders={[201]=true},powerType=6,reserve=60,reason="PREP"}
local other={blocked={[301]=true},spenders={[201]=true},powerType=6,reserve=20,reason="OTHER"}
local ctx={mode="lossless",resolve=function(id) return id==202 and 201 or id end,query=query}
local q={101,201,401,202,301,402}
local function check(c, expected)
    local decision=P.Filter(q,ctx,c)
    assert(#decision.queue==#expected)
    for i,id in ipairs(expected) do assert(decision.queue[i]==id) end
end
check(config,{401,301,402}); check(other,{101,401,402})
amount=55; check(other,{101,201,401,202,402}); check(config,{401,301,402})
amount=95; check(config,{201,401,202,301,402})
amount=94.999; check(config,{401,301,402})
assert(#q==6 and q[1]==101 and q[2]==201)
assert(#P.Filter({101,201},ctx,config).queue==0)
amount=100; costRows=nil; check(config,{401,301,402})
reset()
local toc=assert(io.open("JustACBridge.core/JustACBridge.toc","r")):read("*a")
assert(toc:find("Framework\\ResourcePreparation.lua",1,true)<toc:find("Policies\\DeathKnight\\Frost.lua",1,true))
-- Strict alignment boundary, including adjacent representable doubles.
for _, hidden in ipairs({false,true}) do
    reset(); hiddenCD,hiddenResult=hidden,hidden
    for _, value in ipairs({0,6,17.999999,18-2^-48,18,18+2^-48,18.000001,19,35}) do
        remaining=value
        assert(P.CooldownAbove(101,18,query)==(value>18), tostring(value))
    end
end
-- A lower-precision native curve may collapse adjacent doubles. It MUST NOT
-- turn equality into far: use a proven lower bound or return unknown instead.
reset(); hiddenCD,hiddenResult=true,true
local originalCreate=C_CurveUtil.CreateCurve
C_CurveUtil.CreateCurve=function()
    local curve=originalCreate()
    local add=curve.AddPoint
    function curve:AddPoint(x,y)
        if x==18+2^-48 then x=18 end
        add(self,x,y)
    end
    return curve
end
remaining=18; assert(P.CooldownAbove(101,18,query)==nil)
remaining=18.5; assert(P.CooldownAbove(101,18,query)==nil)
remaining=19; assert(P.CooldownAbove(101,18,query)==true)
remaining=35; assert(P.CooldownAbove(101,18,query)==true)
C_CurveUtil.CreateCurve=originalCreate
for _, mode in ipairs({"throw","nil","secret"}) do
    reset(); durationMode=mode; assert(P.CooldownAbove(101,18,query)==nil)
end
for _, mode in ipairs({"throw","wrong-boundary","linear","secret"}) do
    reset(); hiddenCD=true; curveMode=mode
    assert(P.CooldownAbove(101,18,query)==nil)
end
for _, mode in ipairs({"throw","nil","invalid"}) do
    reset(); hiddenCD=true; resultMode=mode
    assert(P.CooldownAbove(101,18,query)==nil)
end
-- Fresh discrete slots, lower/upper proofs with partial unknowns, no event
-- or timer extrapolation. The public helper contains no class-specific API.
reset()
for count=0,6 do
    for threshold=0,7 do
        assert(P.ReadySlotsAtLeast(6,threshold,function(i) return i<=count end)==(count>=threshold))
    end
end
assert(P.ReadySlotsAtLeast(6,2,function(i) if i<=2 then return true end return opaque end)==true)
assert(P.ReadySlotsAtLeast(6,2,function(i) if i==1 then return opaque end return false end)==false)
assert(P.ReadySlotsAtLeast(6,2,function(i) if i==1 then return true end return opaque end)==nil)
for _, reader in ipairs({function() return opaque end,function() return nil end,function() error("slot failed") end}) do
    assert(P.ReadySlotsAtLeast(6,2,reader)==nil)
end
local slots=2
local runeConfig={blocked={},spenders={[201]=true},powerType=5,reserve=2,allowFree=true,
    resourceAtLeast=function(n) return P.ReadySlotsAtLeast(6,n,function(i) return i<=slots end) end,reason="RUNES"}
costRows={{type=5,cost=2,minCost=2}}
assert(#P.Filter({201,401},ctx,runeConfig).queue==1)
slots=4; assert(#P.Filter({201,401},ctx,runeConfig).queue==2)
slots=3; assert(#P.Filter({201,401},ctx,runeConfig).queue==1)
slots=0; costRows={{type=5,cost=0,minCost=0}}
assert(#P.Filter({201,401},ctx,runeConfig).queue==2) -- free even below reserve
runeConfig.reserve=nil; assert(#P.Filter({201,401},ctx,runeConfig).queue==2)
costRows={{type=5,cost=1,minCost=1}}; assert(#P.Filter({201,401},ctx,runeConfig).queue==1)
runeConfig.reserve=2
for _, reader in ipairs({function() return opaque end,function() error("reader failed") end,function() return nil end}) do
    runeConfig.resourceAtLeast=reader; assert(#P.Filter({201,401},ctx,runeConfig).queue==1)
end
-- Native secret BOOLEAN conversion never treats numeric resource values as
-- booleans and never reads a stale UI resource bar. Both engine constants
-- must self-test before the binary adapter receives hidden 0/1 results.
reset()
local readyBit, binaryBit, nativeBroken
C_CurveUtil.EvaluateColorValueFromBoolean=function(value,yes,no)
    assert(yes==1 and no==0)
    if nativeBroken then return 0.5 end
    if rawequal(value,opaque) then binaryBit=readyBit; return opaque end
    return value and yes or no
end
local function slotQuery(name,value)
    assert(name=="ReadBinaryPredicate" and rawequal(value,opaque)); return true,binaryBit
end
for available=0,6 do
    for needed=0,7 do
        assert(P.ReadySlotsAtLeast(6,needed,function(i) readyBit=i<=available; return opaque end,slotQuery)==(available>=needed))
    end
end
nativeBroken=true
assert(P.ReadySlotsAtLeast(6,2,function() return opaque end,slotQuery)==nil)
C_CurveUtil.EvaluateColorValueFromBoolean=nil
-- Inclusive sequence deadlines: equality must not wait another entire GCD.
for _, hidden in ipairs({false,true}) do
    reset(); hiddenCD,hiddenResult=hidden,hidden
    for _, deadline in ipairs({0.75,1,1.2,1.5,2.5}) do
        for _, delta in ipairs({-0.01,-0.000001,0,0.000001,0.01,20}) do
            remaining=deadline+delta
            assert(P.CooldownAtMost(101,deadline,query)==(remaining<=deadline))
        end
    end
end
for _, mode in ipairs({"throw","nil","secret"}) do
    reset(); durationMode=mode; assert(P.CooldownAtMost(101,1,query)==nil)
end
for _, mode in ipairs({"throw","wrong-boundary","linear","secret"}) do
    reset(); hiddenCD=true; curveMode=mode; assert(P.CooldownAtMost(101,1,query)==nil)
end
for _, mode in ipairs({"throw","nil","invalid"}) do
    reset(); hiddenCD=true; resultMode=mode; assert(P.CooldownAtMost(101,1,query)==nil)
end
reset(); hiddenCD,hiddenResult=true,true
C_CurveUtil.CreateCurve=function()
    local c=originalCreate()
    local add=c.AddPoint
    c.AddPoint=function(self,x,y) add(self,tonumber(string.format("%.7g",x)),y) end
    return c
end
remaining=0.99; assert(P.CooldownAtMost(101,1,query)==true)
remaining=1; assert(P.CooldownAtMost(101,1,query)==nil) -- float cannot distinguish next-double
remaining=1.01; assert(P.CooldownAtMost(101,1,query)~=true)
C_CurveUtil.CreateCurve=originalCreate
for _, hidden in ipairs({false,true}) do
    reset(); hiddenCD,hiddenResult=hidden,hidden
    local clock=280
    GetTime=function() return clock end
    local gcd=1.5/1.75
    remaining=((235+gcd)+45)-clock
    assert(remaining>gcd) -- cancellation/addition error, not a gameplay delay
    assert(P.CooldownAtMost(101,gcd,query)==true)
    remaining=gcd+0.000001
    assert(P.CooldownAtMost(101,gcd,query)==false) -- one microsecond is NOT forgiven
    clock=1000000; remaining=((clock-45+1.2)+45)-clock
    assert(P.CooldownAtMost(101,1.2,query)==true)
    remaining=1.200001; assert(P.CooldownAtMost(101,1.2,query)==false)
    GetTime=nil
end
-- Explicit M5-only capability: M4/unknown contexts retain ordinary spender
-- order and must not even READ costs/resources for an upcoming burst.
do
    local originalCost,originalPower=C_Spell.GetSpellPowerCost,UnitPower
    C_Spell.GetSpellPowerCost=function() error("M4 must not query preparation cost") end
    UnitPower=function() error("M4 must not query preparation resource") end
    for _, mode in ipairs({"preserve","invalid",false,opaque}) do
        ctx.mode=mode
        assert(P.IsEnabled(ctx)==false)
        local d=P.Filter({101,201,401,202},ctx,config)
        assert(#d.queue==3 and d.queue[1]==201 and d.queue[2]==401 and d.queue[3]==202)
        assert(d.reason:find("RESOURCE_PREPARATION_DISABLED_FOR_MODE",1,true))
    end
    ctx.mode=nil; assert(not P.IsEnabled(ctx))
    assert(P.Filter({201},ctx,config).queue[1]==201)
    assert(P.Filter({},ctx,config).queue[1]==nil)
    C_Spell.GetSpellPowerCost,UnitPower=originalCost,originalPower
    ctx.mode="lossless"; reset(); amount=42; costRows={{type=6,cost=35,minCost=35}}
    assert(P.IsEnabled(ctx)==true and #P.Filter({201},ctx,config).queue==0)
    ctx.mode="preserve"; assert(P.Filter({201},ctx,config).queue[1]==201)
    ctx.mode="lossless"; assert(#P.Filter({201},ctx,config).queue==0) -- no mode latch
end
print("resource preparation framework tests passed")
