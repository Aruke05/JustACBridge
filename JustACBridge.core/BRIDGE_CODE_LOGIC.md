# JustACBridge 2.12.37：代码路径与判定逻辑

> 本文是当前实现的代码级说明，不是面向玩家的职业循环翻译。伪代码保留真实函数名、
> 分支顺序、三态返回值和 fail-open/fail-closed 语义，便于与其他 Bridge 实现逐函数对比。

## 1. 加载单元与职责

TOC 加载顺序的主要依赖关系：

```text
Sources/Registry.lua
  ├─ Sources/JustAC.lua                 -- supportSource + raw JustAC queue
  ├─ Sources/Runtime121.lua             -- 火/冰/DK 自有源的三态运行时
  ├─ Sources/Arcane121.lua              -- 独立奥法运行时和状态机
  ├─ Sources/Fire121.lua
  └─ Sources/FrostMage121.lua

Policies/Registry.lua
  ├─ Policies/Mage.lua
  ├─ Policies/Mage/Arcane.lua
  ├─ Policies/Mage/Fire.lua
  └─ Policies/Mage/Frost.lua

Trackers/GroundEffects.lua
Trackers/CooldownReady.lua
JustACBridge.lua                        -- 双路动作解析、导出、事件状态机
```

推荐源只产生 `queueValue[]`：

```lua
queueValue > 0  -- spellID
queueValue < 0  -- -itemID
queueValue == 0 -- invalid
```

最终导出动作由 `JustACBridge.lua/getSpellData()` 构造：

```lua
{
    position,       -- 1=M5/lossless, 2=M4/preserve
    queueValue,     -- 源队列值
    kind,           -- "spell" | "item"
    spellID,        -- effective spell ID
    sourceSpellID,  -- raw queue spell ID
    itemID,
    name,
    icon,
    hotkey,
    plainHotkey,
    offGCD,         -- Policy 对当前 raw/effective spell 的逐动作标记
}
```

## 2. 推荐源选择与能力回落

### 2.1 `automaticRecommendationSourceID()`

```lua
if interface < 120100 or interface > 120199 then
    return "justac"
end

AUTOMATIC_SOURCE_BY_SPEC = {
    MAGE_1 = "arcane121",
    MAGE_2 = "fire121",
    MAGE_3 = "frostmage121",
}

return AUTOMATIC_SOURCE_BY_SPEC[classFile .. "_" .. spec] or "justac"
```

### 2.2 `activateRecommendationSource(preferredID, strict)`

```lua
requestedID = preferredID or "auto"
resolvedID = requestedID == "auto"
    and automaticRecommendationSourceID()
    or requestedID

activeSource = strict and requestedID ~= "auto"
    and SourceRegistry.Get(resolvedID)
    or SourceRegistry.Select(resolvedID)

supportSource = SourceRegistry.Get("justac")
```

### 2.3 `sourceCall(methodName, ...)`

能力查询不是固定调用 JustAC：

```lua
if type(activeSource[methodName]) == "function" then
    return pcall(activeSource[methodName], ...)
end

if supportSource ~= activeSource
    and type(supportSource[methodName]) == "function" then
    return pcall(supportSource[methodName], ...)
end

return false, nil, "unsupported capability"
```

因此 `GetQueue()` 可以来自 `arcane121`，而 `GetSpellHotkey()`、
`GetEffectiveSpellID()`、`IsSpellProcced()`、射程和引导查询仍可来自 JustAC。

## 3. Policy 解析与 M4 保留集合

`Policies/Registry.lua/Resolve(classFile, specIndex, interfaceVersion)`：

1. 复制职业公共规则。
2. 合并专精基础规则。
3. 从 `versions[]` 选择 `minInterface <= interface <= maxInterface` 且
   `minInterface` 最大的补丁。
4. 补丁中的数组字段执行 replace；`add*`/`remove*` 执行增删。
5. 返回一个当前专精不可变快照 `currentPolicy`。

`refreshReservedSpells()` 的真实顺序：

```lua
reservedSpellIDs = {}
currentPolicy = PolicyRegistry.Resolve(...)

for spellID in currentPolicy.reserve do
    addReservedSpell(rawID + effectiveID)
end

if currentPolicy.useDetectedBurstTriggers ~= false then
    for trigger in sourceCall("GetDetectedBurstTriggers") do
        addReservedSpell(trigger.spellID or trigger)
    end
end

for spellID in currentPolicy.reservePassthrough do
    removeReservedSpell(rawID + effectiveID)
end

for spellID in userOverride.include do addReservedSpell(spellID) end
for spellID in userOverride.exclude do removeReservedSpell(spellID) end
```

`isReservedQueueValue(v)`：

```lua
return v < 0                                  -- 所有物品
    or reservedSpellIDs[v]
    or reservedSpellIDs[getEffectiveSpellID(v)]
```

M4 的另外两类排除不等于 `reserve`：

```lua
isReserveExcludedQueueValue(v)
    = rawID in reserveExclusions
      or effectiveID in reserveEffectiveExclusions

isRotationExcludedQueueValue(v)
    = rawID in rotationExclusions
      or effectiveID in rotationEffectiveExclusions
```

`reserveExclusions` 只过滤 M4；`rotationExclusions` 同时过滤 M5/M4。

## 4. 每帧主路径：`refresh()`

插件 `OnUpdate` 以 `UPDATE_INTERVAL = 0` 调用 `refresh()`。核心逻辑按以下顺序运行：

```lua
refreshPlayerMoving()

ok, queue = pcall(activeSource.GetQueue)
if not ok or type(queue) ~= "table" then error end

preserveQueue = queue
separatePreserveQueue = false
if type(activeSource.GetPreserveQueue) == "function" then
    preserveOK, candidate = pcall(activeSource.GetPreserveQueue)
    if preserveOK and type(candidate) == "table" then
        preserveQueue = candidate
        separatePreserveQueue = true
    end
end

lossless = findPolicyCastFollowupRecommendation(1)
losslessQueueOnlyRule = not lossless
    and getActiveSourceQueueOnlyBeyondRule("losslessSourceQueueOnlyBeyond")

if not lossless and losslessQueueOnlyRule then
    lossless = findAllowedSourceQueueRecommendation(queue, rule.allow, 1)
elseif not lossless then
    lossless = findPolicyPriorityCueRecommendation()
        or findSourceBurstCueRecommendation(queue)
        or findMaintenanceRecommendation(1)
        or findSafeRecommendation(queue)
end

if not lossless and not losslessQueueOnlyRule then
    lossless = findPolicyFinalFallback(1)
end

preserveQueueOnly = currentPolicy.preserveSourceQueueOnly == true
preserveQueueOnlyRule = getActiveSourceQueueOnlyBeyondRule(
    "preserveSourceQueueOnlyBeyond")

if preserveQueueOnlyRule then
    preserve = findAllowedSourceQueueRecommendation(
        preserveQueue, rule.allow, 2)
elseif not preserveQueueOnly then
    preserve = findMaintenanceRecommendation(2)
end

if not preserve
    and not preserveQueueOnlyRule
    and not preserveQueueOnly
    and not separatePreserveQueue
    and lossless
    and lossless.plainHotkey ~= ""
    and not isReservedQueueValue(lossless.queueValue)
    and not isReserveExcludedQueueValue(lossless.queueValue)
    and isPreserveSafeQueueValue(lossless.queueValue) then
    preserve = copy(lossless, position=2)
elseif not preserve and not preserveQueueOnlyRule then
    startIndex = preserveQueueOnly and 1
        or playerIsMoving and movementFilter and 1
        or separatePreserveQueue and 1
        or lossless and 2
        or 1

    preserve = findReserveRecommendation(preserveQueue, startIndex)
    if not preserve and not preserveQueueOnly then
        preserve = findPolicyFinalFallback(2)
    end
end

queueReady, gcdRemainingMs = getGcdState()
updateSavedExport({ lossless, preserve })
updateUI({ lossless, preserve })
```

这段顺序是 M5/M4 差异的最终定义。推荐源的第一项并不直接等于导出动作。

`queueReady` 是全局普通 GCD 门控；`data.offGCD` 是逐槽位例外。桌面端计算：

```text
losslessCanPulse = queueReady || lossless.offGCD
preserveCanPulse = queueReady || preserve.offGCD
```

`playerIsCasting`、`channelBlocksInput()` 和 protected-channel latch 在这两个值之前阻断。

## 5. 动作安全谓词

### 5.1 M5：`isSafeQueueValue(v, position)`

```lua
return not isRotationExcludedQueueValue(v)
    and isCastSequenceSafeQueueValue(v)
    and isMovementSafeQueueValue(v, position)
    and isRangeSafeQueueValue(v)
    and isGroundEffectSafeQueueValue(v)
    and not isFailureSuppressedQueueValue(v)
```

### 5.2 M4：`isPreserveSafeQueueValue(v)`

```lua
if currentPolicy.preserveUsesCurrentSafety == true then
    return isSafeQueueValue(v, 2)       -- 12.1 奥法
end
return isHoldSafeQueueValue(v)          -- 普通专精
```

### 5.3 普通 M4：`isHoldSafeQueueValue(v)`

```lua
if v <= 0 then return false end
if isSuccessfulCastResumeDelayed(v, 2) then return false end
if sourceCall("IsChanneled", v) == true then return false end
if sourceCall("IsChanneled", effective(v)) == true then return false end

resumeDelay = getMoveResumeDelay(v, 2)
stationaryResumeSafe = resumeDelay
    and not playerIsMoving
    and now - lastMovementStoppedAt >= resumeDelay
    and C_Spell.GetSpellInfo(effective(v)).castTime == 0

return not rotationExcluded(v)
    and sequenceSafe(v)
    and (stationaryResumeSafe or isSpellMoveCastableNow(v))
    and rangeSafe(v)
    and groundSafe(v)
    and not failureSuppressed(v)
```

注意：普通 M4 不检查“这一帧静止就放行普通读条”，而是直接要求动作满足移动施法谓词。

### 5.4 `isMovementSafeQueueValue(v, position)`

```lua
if invalid(v) then return false end
if successfulCastResumeDelayed(v, position) then return false end
if playerIsMoving and moveCastNever(v) then return false end
if resumeDelay(v, position) and now-lastMovementStoppedAt < delay then return false end

if movementFilter == false or not playerIsMoving then
    return true
end

return v < 0 or isSpellMoveCastableNow(v)
```

### 5.5 `isSpellMoveCastableNow(spellID)`

真实优先顺序：

```lua
if policy.moveCastNever contains spellID then return false end

instantOnly = policy.moveCastInstantOnly contains spellID

if exact moveCastCondition is satisfied then return true end

if not instantOnly
    and (moveCastAlways contains spellID or hasMovementCastBuff()) then
    return true
end

if sourceCall("IsChanneled", spellID) == true then return false end

castTime = C_Spell.GetSpellInfo(effectiveID).castTime
if plain(castTime) and castTime == 0 then return true end

if instantOnly then return false end

if sourceCall("IsSpellProcced", spellID) == true then return true end
return false
```

`moveCastInstantOnly` 的技能不会因为通用移动 Buff 或按钮发光而放行；必须观察到当前
有效法术形态的 `castTime == 0`，或命中专门的 `moveCastCondition`。

### 5.6 可用性、射程、绑定

```lua
isUsableNow(spellID):
    if sourceCall("IsSpellUsable") == false then return false end
    remaining = cooldownRemainingSeconds(spellID)
    return remaining == nil or remaining*1000 <= 120

isRangeSafeQueueValue(v):
    if rangeFilter disabled or v is item then return true end
    return sourceCall("IsConfirmedOutOfRange", v) ~= true

export gate:
    data = getSpellData(v, position)
    return data only if data.plainHotkey ~= ""
```

射程未知 fail-open；策略注入的 maintenance cooldown 未知 fail-closed；源队列动作的
cooldown 未知在 `isUsableNow` 中 fail-open。

## 6. 队列扫描器

### 6.1 M5：`findSafeRecommendation(queue)`

```lua
count = min(#queue, 8)

if findRangeSequenceRecommendation(queue, count) then return it end

primaryBlockedFlags = evaluate(queue[1])

for i = 1, count do
    v = queue[i]
    if numeric_nonzero(v)
        and isSafeQueueValue(v)
        and (v < 0 or isUsableNow(v)) then
        data = getSpellData(v, 1)
        if data and data.plainHotkey ~= "" then
            annotate fallback reason when i ~= 1
            return data
        end
    end
end
return nil
```

### 6.2 M4：`findReserveRecommendation(queue, startIndex)`

```lua
for i = startIndex, min(#queue, 8) do
    v = queue[i]
    if v > 0
        and not isReservedQueueValue(v)
        and not isReserveExcludedQueueValue(v)
        and isUsableNow(v)
        and isPreserveSafeQueueValue(v)
        and bound(v) then
        return action(v, position=2)
    end
end

if preserveSourceQueueOnly then return nil end

highlight = sourceCall("GetHighlightCastSpell")
if highlight is a different, non-reserved, non-excluded,
   usable, preserve-safe and bound spell then
    return action(highlight, position=2)
end
return nil
```

物品永远不会进入 `findReserveRecommendation`，因为该函数要求 `v > 0`。

### 6.3 `findPolicyFinalFallback(position)`

专精兜底不要求射程和普通可用性通过，但仍要求：

```lua
enemy-count rule matches
and proc rule matches
and isSpellKnown(spellID)
and not reserved
and not reserveExcluded
and not rotationExcluded
and movementSafe, where:
    position == 2
        ? isSpellMoveCastableNow(spellID)
        : (not playerIsMoving
            or movementFilter == false
            or isMovementSafeQueueValue(spellID))
and bound
```

这是“最后仍有一个可发送键”的故障兜底，不是源 APL 的新优先级。

## 7. 成功施法状态机

核心在 `UNIT_SPELLCAST_SUCCEEDED` 上更新：

```lua
successfulCastSequenceSerial += 1
successfulCastSequenceStep[configuredSpell] = serial
successfulCastSequenceAt[configuredSpell] = GetTime()

successfulCastResumeTriggerAt[triggerSpell] = GetTime()

pendingCastFollowups[rule] = GetTime()
```

`castSequenceRules` 的动作只有在以下任一条件成立时通过：

```lua
prerequisiteStep > actionStep
    and (withinSeconds absent or elapsed < withinSeconds)

or afterAuraID is positively observable

or effectiveID in passthroughEffectiveSpellIDs
```

`pairedCastRules` 同时约束两端：leader 只有 follower 的归属、绑定、可用性和冷却都明确
就绪时才通过；follower 有 10 秒内的新 leader 成功事件时按顺序通过，否则仅在 leader
被明确证明不可用时允许直接通过。任一读取未知都失败关闭。

`castFollowups` 在 M5/M4 主队列之前执行；技能未知、冷却不是明确 false、窗口过期或
没有绑定都会清除 pending，不会等待并阻塞主队列。

## 8. `Runtime121.lua` 的三态契约

火法、冰法使用：

```lua
context:Known(id)       -> true | false
context:Ready(id)       -> true | false | nil
context:AuraUp(...)     -> true | false | nil
context:AuraAtLeast(...) -> true | false | nil
context:Procced(id)     -> true | false | nil
context:EnemyCount()    -> plain number | nil
context:HealthBelow(...) -> true | false | nil
```

`Ready(id)` 的实现：

```lua
if not Known(id) then return false end
usable = CallBoolean("IsSpellUsable", id)
cooldown = CallBoolean("IsSpellOnCooldown", id)
if usable == nil or cooldown == nil then return nil end
return usable and not cooldown
```

选择和回退：

```lua
context:Choose(spellID, rule, detail, raw)
    -> { spellID, unpack(raw without duplicate spellID) }

context:Fallback(reason, raw)
    -> exact same raw table
```

未知不是 false。源只要无法证明某条更高优先级谓词，就在该位置返回 raw JustAC 队列。

## 9. 奥法源：`Arcane121.lua`

### 9.1 状态

```lua
state = {
    cleanAuraBaseline,
    castSequenceSerial,
    touchCastStep,
    surgeCastAt,
    surgeCastStep,
    surgeTargetGUID,
    orbCastAt,
    lastGCDSpellID,
    lastGCDTargetGUID,
    burstStage,          -- expect-touch
    burstStartedAt,
    burstTargetGUID,
    burstCancelReason,
    decision,
    selectedSpellID,
}
```

序列只由 `UNIT_SPELLCAST_SUCCEEDED` 推进；不从 cooldown 推断“已经施放”。
`PLAYER_TARGET_CHANGED`、`UNIT_HEALTH/UNIT_FLAGS`、施法失败/中断和脱战负责撤销凭据。
目标凭据必须来自仍存活、可攻击且 GUID 为 plain string 的当前目标。

### 9.2 `selectQueue(raw, preserve)` 外层顺序

```lua
assert scope == MAGE_1@120100..120199 else fallback
hero = Known(SPLINTERING_SORCERY) ? spellslinger
     : Known(SPELLFIRE_SPHERES) ? sunfury
     : nil
if not hero then fallback end

if not combat then fallback("precombat-delegate-surge-first") end

if not preserve and burstStage exists then
    assert current hostile target GUID == burstTargetGUID
    assert GetTime() - burstStartedAt < 10
    choose expected spell for stage
    -- readiness unknown => cancel + fallback
    -- positively invalid => cancel + continue ordinary APL
end

surgeReady = Ready(ARCANE_SURGE)
touchReady = Ready(TOUCH)

if not preserve then
    if surgeReady == unknown then fallback(raw without TOUCH) end
    if touchReady == unknown then fallback(raw without SURGE) end
    if touchReady and recentSuccessfulSurgeOnSameTarget(10s) then choose TOUCH end
    if surgeReady and touchReady then choose SURGE end
    if surgeReady and not touchReady then raw = raw without SURGE end
    if not surgeReady and touchReady then choose TOUCH end
    if not touchReady then raw = raw without TOUCH end
end

if hero == spellslinger and first Orb not confirmed this combat then
    if Ready(ARCANE_ORB) == true then choose ARCANE_ORB end
    if Ready(...) == nil then fallback end
end

if hero == sunfury
    and Procced(MISSILES) == true
    and AuraAtLeast(SALVO, 12) == false
    and Ready(MISSILES) == true then
    choose MISSILES
end

charges = GetClassResourcePoints()
if charges unknown then fallback end

return hero == spellslinger
    ? select Spellslinger branches
    : select Sunfury branches
```

### 9.2.1 大爆发短状态机与目标凭据

```text
Surge UNIT_SPELLCAST_SUCCEEDED on GUID A
  -> EXPECT_TOUCH
Touch UNIT_SPELLCAST_SUCCEEDED on GUID A
  -> NORMAL
```

下列任一条件调用 `cancelBurstSequence()`：当前目标 GUID 不是 A、目标死亡或不可攻击、
触失败/中断、出现非预期 GCD、触不可用、目标状态变为 unknown，或从涌动
成功起达到 10 秒。取消后同一刷新立即回到普通 APL；只有 unknown readiness 按高优先级
未知规则回退 JustAC。

策略层的 `pairedCastRules.targetBound=true` 为原始 JustAC 回退队列提供同一 GUID 门。
M5 不再要求上一弹幕/Bolt，也不再使用剩余冷却阈值；M4 仍过滤涌动和触。

### 9.3 疾咒师普通表的代码顺序

```text
Prismatic Bolt when Salvo >= 14
  └─ 若第一条的其他 OR 分支仍未知，立即 fallback
Orb Mastery line
  └─ Orb ready 且目标数未知时 fallback
Barrage after Surge at Salvo threshold (Orb Barrage ? 15 : 10)
Barrage at four charges and Salvo threshold (Orb Barrage ? 19 : 20)
Missiles when Clearcasting and Salvo < 15
  └─ 三层 Clearcasting/AoE 子条件未知时 fallback
unconditional Prismatic Bolt when active
Orb when charges < 3
Arcane Pulse when charges < 3 and Surge aura proven absent
Arcane Blast terminal
```

### 9.4 日怒普通表的代码顺序

```text
Prismatic Bolt when active and Arcane Soul is false
  └─ set-bonus higher branch unknown => fallback
Barrage when Arcane Soul
Barrage when Salvo >= 9 and Touch ready
Barrage when charges == 4, Salvo == 25 and (Surge down or Surge remains >= 1.51s)
  └─ Surge 光环/剩余时间不能精确证明时 fallback
Barrage when charges == 4, Salvo >= 12 and Clearcasting
  └─ unresolved enemy-dependent branch => fallback
unconditional Prismatic Bolt when active
Orb when charges < 1
Arcane Pulse when charges < 1
  └─ Pulse ready but enemy-dependent branch unresolved => fallback
Arcane Blast terminal
```

### 9.5 Arcane exact-order fallback

`fallback=true` 不注入技能，也不改变 JustAC 剩余动作的相对顺序：

```lua
selected = raw
selected = removeOnlyExplicitSafetyViolations(selected)
assert(relativeOrder(selected) == relativeOrderOfSameActions(raw))
```

显式安全过滤包括 Touch 的同目标凭据、M4 保留、移动/引导、方向/地面技能以及技能
归属/绑定。它们只能删除不合法动作；不得把 Blast 移到 Barrage 之前，也不得补入 raw
中不存在的 Blast。只有 `selectQueue` 完整证明某条自有 APL 谓词时才能 `choose()` 覆盖。

`GetQueue()` 调用 `selectQueue(raw, false)`；`GetPreserveQueue()` 调用
`selectQueue(raw, true)`。`preserve=true` 只删除源内的 Surge/Touch 分支，其他普通分支
保持相同。

## 10. 火法源：`Fire121.lua`

### 10.1 Proc 分类

```lua
if HotStreak aura or Hyperthermia aura then return "instant" end
if Pyroclasm aura then return "pyroclasm" end
if glow == false and all three auras are not true then return nil end
if glow == true but aura identity unresolved then return "unknown" end
if all auras explicitly false then return nil end
return "unknown"
```

### 10.2 `selectQueue(raw)`

```lua
scope/hero/hostile-target checks else fallback
if raw[1] < 0 then fallback("active-item-timing-delegated") end

if not combat then chooseIfReady(PYROBLAST) else fallback end

enemies = EnemyCount() or fallback
proc = procKind()
combustion = AuraUpOrRecentCast(COMBUSTION, minimum=9)

if combustion == true then
    return selectCombustion(raw, hero, enemies, proc)
end
if combustion == nil and IsSpellOnCooldown(COMBUSTION) == true then fallback end

combustionReady = Ready(COMBUSTION) or fallback on nil
heldForFirestarter = combustionReady
    and Known(FIRESTARTER)
    and not HealthBelow(target, 90)

if combustionReady and not heldForFirestarter then
    if sunfury and proc == instant then spender() end
    if proc == unknown then fallback end

    if sunfury and Known(SUNFURY_EXECUTION) and Ready(METEOR) then
        choose METEOR
    end

    if confirmed precast completed less than 2 seconds ago then
        choose COMBUSTION
    end

    precast = proc == pyroclasm
        ? (enemies >= 3 and Known(FUEL_THE_FIRE) ? FLAMESTRIKE : PYROBLAST)
        : sunfury
            ? ((enemies >= 4 or target<30) ? SCORCH : FIREBALL)
            : FROSTFIRE_BOLT
    choose precast and record state.combustionPrecast
end

clear precast state
return selectFiller(...)
```

### 10.3 燃烧内 `selectCombustion`

Meteor 是第一段：

```lua
if Ready(METEOR) then
    if sunfury then
        below2 = CastAge(COMBUSTION)<7 ? false : AuraRemainsBelow(2)
        if below2 == nil then fallback end
        if not below2 then choose METEOR end
    end
    if frostfire then
        burnout = Known(BURNOUT)
        below = AuraRemainsBelow(burnout and 8 or 2)
        if below == nil then fallback end
        if burnout and below or not burnout and not below then choose METEOR end
    end
end
```

之后：

```text
instant proc -> Pyro/Flamestrike spender
pyroclasm -> fallback（缺少 cast-vs-remains 精确比较）
Heating Up -> Fire Blast
Heat Shimmer or (target<30 and Scald) or Sunfury -> Scorch
terminal -> Frostfire Bolt or Fireball
```

### 10.4 填充 `selectFiller`

```text
Meteor:
  Frostfire and not combustionReady and not heldForFirestarter
  Sunfury and Blast Zone and a prior Combustion event exists

instant proc:
  spender(allowFlamestrike = not heldForFirestarter)

pyroclasm:
  Sunfury -> spender
  Frostfire with >=2 Pyroclasm -> spender
  otherwise fallback for cooldown-remains branch

Heating Up -> Fire Blast
Heat Shimmer or (target<30 and Scald) -> Scorch
terminal -> Frostfire Bolt or Fireball
```

`GetPreserveQueue()` 不调用上述逻辑，直接返回 `context:RawQueue()`。

## 11. 冰法源：`FrostMage121.lua`

### 11.1 开场状态

```lua
opener = { ray=false, flurry=false, orb=false }
```

只在对应 `UNIT_SPELLCAST_SUCCEEDED` 后置 true；进出战斗全部清零。

```lua
frostfire openingOrder = {
    RAY,
    FLURRY if Known(WINTERTIDE),
    ORB,
}

spellslinger openingOrder = {
    FLURRY if Known(WINTERTIDE),
    ORB,
    RAY,
}
```

### 11.2 `selectQueue(raw)` 外层

```lua
scope/hero/target checks else fallback
if raw[1] is item then fallback end

if not combat then
    if enemies >= blizzardThreshold(hero) then choose BLIZZARD end
    choose GLACIAL_SPIKE if ready
    choose FROSTBOLT if ready
    fallback
end

enemies or fallback
walk openingOrder; choose first not-confirmed ready action

if Ray AtMaxCharges then choose Ray end

if frostfire and enemies>2 and Comet ready
   and previousGCD(2) is not Spike then
    fallback("comet-end-of-fight-timing-delegated")
end

brain  = procOrAura(FLURRY, BRAIN_FREEZE) or fallback
fof1   = procOrAura(ICE_LANCE, FINGERS_OF_FROST) or fallback
fof2   = AuraAtLeast(FINGERS_OF_FROST, 2)
spike  = glacialProc() or fallback
thermal = AuraUp(THERMAL_VOID)

return hero == frostfire
    and selectFrostfire(...)
    or selectSpellslinger(...)
```

### 11.3 霜火普通表顺序

```text
Glacial Spike when spike proc/ready
Comet Storm at enemies<=2 or exact two-GCD-after-Spike branch
Brain Freeze Flurry when Thermal Void false
Ice Lance at FoF>=2
Ray before Orb when Hand of Frost 4 absent
Frozen Orb
Blizzard at dynamic threshold or enemies>=3 with Freezing Rain
Ice Lance at FoF with Thermal Void
Ice Lance at target Freezing>=12
Flurry when ready
Ice Nova -> Cone of Cold at enemies>=5 + Cone of Frost + Ray ready + no empowerment
Ray at enemies<=2, or at AoE when Frostfire Empowerment is false
Glacial Spike terminal resource action
Frostbolt terminal
```

`Rapid Refreezing` 的时间比较、Ray tick clip、无法读取的 empowerment/thermal/stack
会在对应优先级处立即 fallback，不继续执行低优先级自有动作。

### 11.4 疾咒师普通表顺序

```text
Comet Storm
Brain Freeze Flurry when Thermal Void false
Ice Lance at FoF>=2
Frozen Orb
Glacial Spike when proc/ready
Blizzard when Freezing Rain and dynamic threshold
Ice Lance at FoF
Ice Lance at target Freezing>=6
Ray at enemies>=3
  └─ enemies<3 requires unknown icicle count => fallback
Flurry when ready
Ice Nova -> Cone of Cold at enemies>=4 + Cone of Frost
Blizzard at general dynamic threshold
Glacial Spike terminal resource action
Frostbolt terminal
```

`GetPreserveQueue()` 直接返回 `context:RawQueue()`。

## 12. 三系 12.1 Policy 实值

### 12.1 奥法

```lua
reserve = { 365350, 321507 }            -- Surge, Touch
useDetectedBurstTriggers = false
offGCD = { 321507 }
pairedCastRules = {
    { leaderSpellID = 365350, followerSpellID = 321507, withinSeconds = 10 },
}
preserveUsesCurrentSafety = true
rotationEffectiveExclusions = { 1449 }
protectedChannels = { 5143 }
maintenanceBuffs = {
    PrismaticBarrier: lossless=false, preserve=true, reserveCharges=0
}
moveCastConditions = {
    Missiles: requires Slipstream + Clearcasting aura,
              probeWhenUsable=true when aura is hidden;
              first failure blocks until confirmed movement stop,
              STOP cancels current probe for one full refresh only;
              a later stationary Missiles recommendation is a new instance,
              secret-speed STOP debounce blocks probe re-arming for 250ms,
    ArcaneBlast: requires PresenceOfMind aura,
}
moveCastNever = { ArcaneOrb raw/compat IDs }
moveCastResumeDelays = { Orb: M5/M4 observed-stationary 2s, including load/reload }
successfulCastResumeDelays = { Orb after Blink/Shimmer: M5/M4 2s }
```

### 12.2 火法

```lua
reserve = { COMBUSTION, METEOR }
reserveExclusions = { FLAMESTRIKE }
moveCastAlways = { SCORCH }
moveCastInstantOnly = { PYROBLAST, FLAMESTRIKE }
maintenanceBuffs = {
    BlazingBarrier: lossless=false, preserve=true, reserveCharges=1
}
```

### 12.3 冰法

```lua
reserve@12.1 = { RAY_OF_FROST }
useDetectedBurstTriggers = false
reserveExclusions = { FROZEN_ORB, RAY, BLIZZARD, CONE_OF_COLD }
protectedChannels = { RAY }
moveCastNever = { GLACIAL_SPIKE legacy/current }
moveCastInstantOnly = { FROSTBOLT, FROSTFIRE_BOLT forms, BLIZZARD }
fallbackActions = { ICE_LANCE }
maintenanceBuffs = {
    IceBarrier: lossless=true, preserve=true, reserveCharges=1
}
```

## 13. 引导/读条状态与协议位

`channelBlocksInput()`：

```lua
if playerIsChanneling and channel in protectedChannels then return true end
return playerIsChanneling
    and not playerIsMoving
    and channel not in clipChannels
```

像素包 `flags`：

```text
0x01 M5 action exists
0x02 M5 action is item
0x04 M5 hotkey exists
0x08 M4 action exists
0x10 M4 action is item
0x20 M4 hotkey exists
0x40 channelBlocksInput()
0x80 playerIsCasting
```

协议 v3：

```text
bytes  1..3   = "JAC"
byte   4      = protocol version
bytes  5..6   = sequence uint16
byte   7      = flags
bytes  8..10  = M5 ID uint24
byte   11     = M5 hotkey length
bytes 12..35  = M5 hotkey UTF-8, max 24 bytes
bytes 36..38  = M4 ID uint24
byte   39     = M4 hotkey length
bytes 40..63  = M4 hotkey UTF-8, max 24 bytes
byte   64     = bit0 queueReady; bit1 moving(v4); bit2 movementFilter(v4);
                bit3 M5 offGCD; bit4 M4 offGCD
bytes 65..66  = gcdRemainingMs uint16
bytes 67..69  = sum1, sum2, rolling
bytes 70..72  = "END"
```

`getGcdState()` 读取 `C_Spell.GetSpellCooldown(61304)`：

```lua
remainingMs = ceil((startTime + duration - GetTime()) * 1000)
queueReady = remainingMs <= 120
```

## 14. Windows 映射器代码路径

```text
WowPixelReader.Run()
  -> capture WoW client rectangle
  -> PixelProtocol.DecodePixels()
  -> PixelProtocol.DecodeValidated()
  -> MainForm.OnPixelUpdate()
  -> M5Hook.UpdateActions()
  -> low-level mouse/keyboard hook
  -> M5Hook.Pulse()
  -> HotkeyBinding.Send()
  -> user32!SendInput
```

关键常量：

```csharp
M5Hook.RepeatIntervalMs = 20;
MainForm.ArcaneExplosionStabilityDelayMs = 100;
ProtectedChannelStartTimeoutMs = 2000;
```

`PixelProtocol.DecodeValidated()` 只有在以下全部成立时构造 `Packet`：

```text
header/version/tail valid
Fletcher sum1 matches
Fletcher sum2 matches
rolling checksum matches
hotkey lengths <= 24
```

Hook 线程只在以下条件同时满足时 pulse：

```text
physical trigger is held
mapping enabled
packet/action valid
action has supported binding
slotCanPulse == (queueReady || action.offGCD)
packet is not IsBusy
protected-channel latch does not block
optional stability delay has completed
repeat gate admits current binding
```

发送是完整 key-down/key-up 或 mouse-down/mouse-up，不保持注入键的 down 状态。

## 15. 用诊断日志验证具体分支

```text
/jacb source auto
/jacb debug on
/jacb debug
```

关键行与代码对应：

```text
SNAP            refresh() 输入状态
QUEUE           activeSource.GetQueue()
PQUEUE          activeSource.GetPreserveQueue()
SOURCE_DECISION source Choose/Fallback 的 rule/reason
SELECT          最终 M5/M4 动作
Qn              每个队列项的 movement/sequence/usable/binding 判定
FALLBACK        policy final fallback 的逐条件结果
```

自有源命中：

```text
SOURCE_DECISION owner=<source> action=<id> rule=<rule> ... fallback=false
```

原样回退 JustAC：

```text
SOURCE_DECISION owner=<source> action=nil rule=fallback.justac
                reason=<reason> fallback=true
```

## 16. 对比其他实现时应逐项检查的代码差异

```text
1. GetQueue 是替换 APL，还是只改 JustAC queue[1]？
2. unknown/secret 在每个谓词是 fail-open、fail-closed 还是被当成 false？
3. Ready 是否先调用 IsPlayerSpell/IsSpellKnown？
4. M4 是否拥有独立 GetPreserveQueue？
5. M4 是仅删除 cooldown，还是调用 always-held cast/channel safety？
6. raw ID 和 effective/display ID 的排除规则是否区分？
7. 是否要求最终动作存在真实 hotkey？
8. 成功施法序列是否依赖 UNIT_SPELLCAST_SUCCEEDED，还是猜 cooldown/timer？
9. protected channel 是等待真实 stop，还是按固定持续时间释放？
10. range unknown 是 fail-open 还是误判超距？
11. direction/ground spell 是否存在自动瞄准的可靠输入？
12. GCD 是全 SpellQueueWindow 预填，还是只在最后 120ms commit？
13. 桌面解码是否在一次帧撕裂时仍会更新动作？
14. 功能键持续按住时是否仍跟随新的 sequence/action？
```
