# 职业策略扩展

`Registry.lua` 是唯一公共入口；策略严格按“职业公共层 + 单专精文件”维护，只登记
数据，不参与像素协议、按键解析或 JustAC 队列读取。

当前目录结构：

```text
Policies/Mage.lua                 # 法师三系公共规则
Policies/Mage/Arcane.lua          # 奥术专精全部规则
Policies/Mage/Fire.lua            # 火焰专精全部规则
Policies/Mage/Frost.lua           # 冰霜专精全部规则
Policies/DeathKnight.lua          # 死亡骑士三系公共规则
Policies/DeathKnight/Blood.lua    # 鲜血专精全部规则
Policies/DeathKnight/Frost.lua    # 冰霜专精全部规则
Policies/DeathKnight/Unholy.lua   # 邪恶专精全部规则
```

专精文件通过 `RegisterSpec("CLASSFILE", specIndex, definition)` 原子登记完整定义。
改版时可直接整体替换一个专精文件，不会触碰同职业的其他专精。

## 新增职业

1. 新建 `Policies/<ClassFile>.lua`，只放职业公共规则，并调用
   `JustACBridgePolicyRegistry.RegisterClass("CLASSFILE", definition)`。
2. 每个专精新建 `Policies/<ClassFile>/<Spec>.lua`，调用
   `JustACBridgePolicyRegistry.RegisterSpec("CLASSFILE", specIndex, definition)`。
3. 在 `JustACBridge.toc` 中先加载职业公共文件，再逐一加载其专精文件。

没有登记策略的职业仍可工作：Bridge 会使用 JustAC 当前专精检测到的
`Burst Trigger`，只是没有 Bridge 内置兼容表。

## 游戏版本变动

稳定的默认规则放在专精的 `reserve` 中。职业或专精还可以登记：

- `reserveExclusions`：保留爆发版本始终跳过、仅允许无损版本释放的技能。
- `reserveEffectiveExclusions`：同样只约束保留爆发版，但仅在队列按钮解析后的“当前
  实际法术 ID”命中时排除；适合基础按钮会被有效天赋技能替换、不能整族屏蔽的情况。
- `rotationExclusions`：从无损版和保留爆发版同时排除的非循环工具技能；用于过滤
  推荐源或突进模块误注入的控制/位移按钮。
- `rotationEffectiveExclusions`：从两路排除当前实际法术，但不连带排除占用同一基础
  按钮的天赋替换/动态 Proc 形态。
- `reservePassthrough`：即使推荐源把技能识别为爆发触发器，保留爆发版仍允许它
  正常通过；适合新版本已移除爆发联动、但旧推荐源配置可能仍残留的技能。
- `moveCastAlways`：自身带读条，但天生允许移动施放的技能。
- `moveCastBuffs`：激活后允许该职业移动施法的玩家 Buff。
- `moveCastNever`：移动时始终跳过的硬读条技能，优先于移动 Buff 和 Proc 判断。
- `moveCastInstantOnly`：忽略 Proc 高亮和移动施法 Buff；仅在当前有效法术形态被
  API 明确报告为零读条时允许。
- `moveCastConditions`：只对指定 `spellID` 生效的移动施法例外；可用
  `requiresSpell` 要求已学习的天赋/法术，并用 `auraID` 要求当前玩家 Buff。配置的
  条件全部可确认时才允许，未知状态保守跳过。
- `clipChannels`：循环明确要求可在 GCD 末主动截断的引导技能。引导状态仍会导出，
  但不会一直占用动作队列。
- `rangeSequenceRules`：只在目标被明确判定超过指定距离时调整技能先后；距离未知时
  不改 JustAC 原顺序。
- `groundEffects`：成功放置后按持续时间跟踪的场地技能，可在仍有效时抑制重复推荐。
- `fallbackActions`：仅在玩家移动且 JustAC 的前 8 项没有安全可执行动作时使用的
  有序兜底。支持 `spellID`、`minEnemies`、`maxEnemies`、`requireProc` 和显示用
  `label`；仍必须通过已学习、可用、射程、移动安全和快捷键检查。
- `preserveSourceQueueOnly`：M4 只允许选择推荐源当前队列中真实存在的动作；禁用 M4
  的维护技能注入、M5 结果复用、高亮兜底和专精最终兜底。用于不能把 Proc/高亮近似
  当作推荐源已选择动作的专精；M5 不受影响。
- `losslessSourceQueueOnlyBeyond`：用 `beyond` 指定距离、`allow` 指定允许法术；当
  推荐源能明确证明目标超过该距离时，M5 只从当前原队列选择允许法术，禁用其他队列
  动作和所有注入/兜底；距离未知时不改变原行为。
- `preserveSourceQueueOnlyBeyond`：与上一项相同，但作用于 M4，并继续执行 M4 的爆发
  保留与按住安全过滤。
- `maintenanceBuffs`：自身 Buff 明确不存在时插入的维护技能。每项登记
  `spellID`、`auraID`，并用 `lossless`/`preserve` 指定作用于哪一路；只有光环缺失、
  法术已学习、冷却明确就绪且快捷键已绑定时才会加入；`reserveCharges` 可要求自动
  施放后仍保留指定充能数，任何未知状态都保守跳过。

版本差异放在 `versions`，无需修改主循环：

```lua
[2] = {
    id = "example",
    name = "示例",
    revision = 2,
    preserveSourceQueueOnly = true,
    losslessSourceQueueOnlyBeyond = {
        beyond = 5,
        allow = { 8001 },
    },
    preserveSourceQueueOnlyBeyond = {
        beyond = 5,
        allow = { 8001 },
    },
    reserve = { 1001, 1002 },
    reservePassthrough = { 1000 },
    reserveExclusions = { 1003 },
    reserveEffectiveExclusions = { 1005 },
    rotationExclusions = { 1004 },
    rotationEffectiveExclusions = { 1006 },
    moveCastAlways = { 3001 },
    moveCastBuffs = { 4001 },
    moveCastNever = { 4002 },
    moveCastInstantOnly = { 4003 },
    moveCastConditions = {
        { spellID = 4004, requiresSpell = 4005, auraID = 4006 },
    },
    clipChannels = { 5001 },
    rangeSequenceRules = {
        {
            requiresSpell = 6001,
            beyond = 20,
            defer = { 6002 },
            prefer = { 6003 },
        },
    },
    groundEffects = {
        {
            id = "example-ground",
            name = "示例场地",
            spells = { 7001, 7002 },
            duration = 10,
            suppressRepeat = true,
        },
    },
    fallbackActions = {
        { spellID = 8001, requireProc = true, label = "触发优先" },
        { spellID = 8002, minEnemies = 5, label = "五目标兜底" },
        { spellID = 8003, label = "通用兜底" },
    },
    maintenanceBuffs = {
        {
            spellID = 9001,
            auraID = 9001,
            lossless = true,
            preserve = true,
            reserveCharges = 1,
        },
    },
    versions = {
        {
            id = "12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 3,
            addReserve = { 1003 },
            removeReserve = { 1001 },
        },
        {
            id = "13.0",
            minInterface = 130000,
            revision = 4,
            reserve = { 2001, 2002 }, -- 完整替换
        },
    },
}
```

选择规则：

- Interface 区间匹配时，`minInterface` 最大的补丁生效。
- `reserve` 表示完整替换；`removeReserve` 后执行 `addReserve`。
- 爆发透传支持 `reservePassthrough` 完整替换和
  `add/removeReservePassthrough` 增量修改；它在推荐源爆发项合并后执行，玩家
  `/jacb reserve add/remove` 覆盖仍最后执行。
- 保留版技能排除支持 `reserveExclusions` 完整替换和
  `add/removeReserveExclusions` 增量修改。
- 当前实际法术排除支持 `reserveEffectiveExclusions` 完整替换和
  `add/removeReserveEffectiveExclusions` 增量修改。
- 全循环排除支持 `rotationExclusions` 完整替换和
  `add/removeRotationExclusions` 增量修改，并同时约束两个导出动作。
- 当前实际法术的全循环排除支持 `rotationEffectiveExclusions` 完整替换和
  `add/removeRotationEffectiveExclusions` 增量修改，并同时约束两个导出动作。
- 移动规则对应支持 `moveCastAlways/moveCastBuffs` 完整替换，以及
  `add/removeMoveCastAlways`、`add/removeMoveCastBuffs` 增量修改；
  `moveCastNever` 同样支持完整替换和 `add/removeMoveCastNever`；
  `moveCastInstantOnly` 同样支持完整替换和 `add/removeMoveCastInstantOnly`；
  条件移动规则支持 `moveCastConditions` 完整替换和 `addMoveCastConditions` 追加。
- 引导规则支持 `clipChannels` 完整替换和 `add/removeClipChannels` 增量修改；
  距离顺序规则支持 `rangeSequenceRules` 完整替换和 `addRangeSequenceRules` 追加。
- 场地规则支持 `groundEffects` 完整替换和 `addGroundEffects` 追加。
- 兜底规则支持 `fallbackActions` 完整替换和 `addFallbackActions` 追加。
- Buff 维护规则支持 `maintenanceBuffs` 完整替换和 `addMaintenanceBuffs` 追加。
- 玩家 `/jacb reserve add/remove` 最后执行，始终高于内置策略。
- SavedVariables 继续使用稳定键 `CLASSFILE_<专精序号>`，拆文件或升版本不会丢失
  现有覆盖。
