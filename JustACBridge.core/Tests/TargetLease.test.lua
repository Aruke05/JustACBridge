dofile("JustACBridge.core/Framework/TargetLease.lua")
local secret=setmetatable({}, {__tostring=function() error("secret logged") end,
    __eq=function() error("secret compared") end})
function issecretvalue(v) return rawequal(v,secret) end
local exists,attackable,dead,guid=true,true,false,"A"
function UnitExists() return exists end
function UnitCanAttack() return attackable end
function UnitIsDeadOrGhost() return dead end
function UnitGUID() return guid end
local lease=JustACBridgeTargetLease.New()
local a=lease:Read(); assert(a.valid==true and a.key)
guid=secret; local hidden=lease:Read()
assert(hidden.key==a.key and hidden.valid==true and hidden.evidence:find("guid=secret",1,true))
guid=nil; assert(lease:Read().key==a.key)
guid="A"; assert(lease:Read().key==a.key)
guid="B"; local b=lease:Read(); assert(b.key~=a.key and b.valid==true)
guid=secret; lease:Reset(); local c=lease:Read(); assert(c.key~=b.key)
-- An unknown validity read cannot grant action permission, but it does not
-- falsify the identity of an already-established target epoch or cast receipt.
attackable=secret; local unknown=lease:Read()
assert(unknown.valid==nil and unknown.key==c.key)
assert(unknown.evidence:find("attackable=secret",1,true))
lease:Reset(); assert(lease:Read().key==nil)
attackable=true; local d=lease:Read(); assert(d.key and d.valid==true)
dead=true; assert(lease:Read().valid==false and lease:Read().key==nil)
dead=false; assert(lease:Read().key~=d.key)
exists=false; assert(lease:Read().valid==false)
exists=true; attackable=false; assert(lease:Read().valid==false)
attackable=true
for _, name in ipairs({"UnitExists","UnitCanAttack","UnitIsDeadOrGhost"}) do
    local original=_G[name]
    for _, mode in ipairs({"secret","nil","error","missing","wrong-type"}) do
        lease:Reset()
        _G[name]=mode~="missing" and function()
            if mode=="secret" then return secret end
            if mode=="error" then error("API fault") end
            if mode=="wrong-type" then return 1 end
            return nil
        end or nil
        local s=lease:Read(); assert(s.valid==nil and s.key==nil)
        _G[name]=original
        assert(lease:Read().valid==true)
    end
end
-- Explicit negative evidence wins over other unknown fields.
exists=false; attackable=secret; dead=secret
assert(lease:Read().valid==false)
exists,attackable,dead=true,true,false
local second=JustACBridgeTargetLease.New()
assert(second:Read().key~=lease:Read().key)
local saved=second:Read().key; lease:Reset(); assert(second:Read().key==saved)
local f=assert(io.open("JustACBridge.core/JustACBridge.toc","r")); local toc=f:read("*a"); f:close()
assert(toc:find("Framework\\TargetLease.lua",1,true)<toc:find("\nJustACBridge.lua",1,true))
print("target lease tests passed")
