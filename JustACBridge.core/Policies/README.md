# 职业策略扩展

`Registry.lua` 是唯一公共入口；职业文件只登记数据，不参与像素协议、按键解析或
JustAC 队列读取。

## 新增职业

1. 新建 `Policies/<ClassFile>.lua`。
2. 调用 `JustACBridgePolicyRegistry.RegisterClass("CLASSFILE", definition)`。
3. 在 `JustACBridge.toc` 的 `JustACBridge.lua` 之前增加该文件。

没有登记策略的职业仍可工作：Bridge 会使用 JustAC 当前专精检测到的
`Burst Trigger`，只是没有 Bridge 内置兼容表。

## 游戏版本变动

稳定的默认规则放在专精的 `reserve` 中。职业或专精还可以登记：

- `reserveExclusions`：保留爆发版本始终跳过、仅允许无损版本释放的技能。
- `moveCastAlways`：自身带读条，但天生允许移动施放的技能。
- `moveCastBuffs`：激活后允许该职业移动施法的玩家 Buff。
- `moveCastNever`：移动时始终跳过的硬读条技能，优先于移动 Buff 和 Proc 判断。
- `moveCastProcNever`：忽略不可靠的 Proc 高亮；仅在基础瞬发、API 明确报告零读条或
  移动施法 Buff 生效时允许。
- `clipChannels`：循环明确要求可在 GCD 末主动截断的引导技能。引导状态仍会导出，
  但不会一直占用动作队列。
- `rangeSequenceRules`：只在目标被明确判定超过指定距离时调整技能先后；距离未知时
  不改 JustAC 原顺序。
- `groundEffects`：成功放置后按持续时间跟踪的场地技能，可在仍有效时抑制重复推荐。

版本差异放在 `versions`，无需修改主循环：

```lua
[2] = {
    id = "example",
    name = "示例",
    revision = 2,
    reserve = { 1001, 1002 },
    reserveExclusions = { 1003 },
    moveCastAlways = { 3001 },
    moveCastBuffs = { 4001 },
    moveCastNever = { 4002 },
    moveCastProcNever = { 4003 },
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
- 保留版技能排除支持 `reserveExclusions` 完整替换和
  `add/removeReserveExclusions` 增量修改。
- 移动规则对应支持 `moveCastAlways/moveCastBuffs` 完整替换，以及
  `add/removeMoveCastAlways`、`add/removeMoveCastBuffs` 增量修改；
  `moveCastNever` 同样支持完整替换和 `add/removeMoveCastNever`；
  `moveCastProcNever` 同样支持完整替换和 `add/removeMoveCastProcNever`。
- 引导规则支持 `clipChannels` 完整替换和 `add/removeClipChannels` 增量修改；
  距离顺序规则支持 `rangeSequenceRules` 完整替换和 `addRangeSequenceRules` 追加。
- 场地规则支持 `groundEffects` 完整替换和 `addGroundEffects` 追加。
- 玩家 `/jacb reserve add/remove` 最后执行，始终高于内置策略。
- SavedVariables 继续使用稳定键 `CLASSFILE_<专精序号>`，拆文件或升版本不会丢失
  现有覆盖。
