# 推荐源接口

Bridge 核心不再直接读取 JustAC。推荐模块通过
`JustACBridgeRecommendationSources.Register(id, source)` 登记。

## 最小自定义源

JustAC 仍安装时，自定义源只需返回按优先级排列的法术/物品 ID：

```lua
JustACBridgeRecommendationSources.Register("my-rotation", {
    name = "我的循环",
    GetQueue = function()
        return {
            49184, -- 正数：法术 ID
            49020,
            -12345, -- 负数：物品 ID
        }
    end,
})
```

使用：

```text
/jacb source list
/jacb source auto
/jacb source my-rotation
```

`auto` 是默认模式：Interface 12.1 下，奥法、火法、冰法分别解析为 `arcane121`、
`fire121`、`frostmage121`；死亡骑士与其他专精解析为 `justac`。`frostdk121` 与
`unholydk121` 仅保留为显式 `/jacb source` 可选的实验源。切换专精或天赋时会重新
解析，但不会覆盖玩家显式选择的自定义源。

未实现的快捷键、射程、可用性、Proc、引导识别等能力会回退给已安装的 JustAC
适配器，因此替换推荐算法时无需复制动作栏扫描代码。

源还可以实现 `GetPreserveQueue()`，为 M4 提供与 M5 `GetQueue()` 完全不同的原始
队列；未实现时两种模式共享 `GetQueue()`。`GetDecisionTrace()` 可返回一行决策原因，
Bridge 会以 `SOURCE_DECISION` 写入诊断日志。

内置 12.1 自有源统一遵循：M5 先做本专精可完整证明的优先级，遇到不可观测的更高
条件立即原样回退 JustAC。火法、冰法及手动启用的冰/邪 DK 实验源，其 M4 返回原始 JustAC 队列；
奥法 M4 是专属例外，继续运行同一个 `arcane121` 优先级，但不选择奥术涌动和
大法师之触。策略层仍会过滤爆发、物品、不可移动读条/引导/蓄力和无法安全瞄准的
方向/地面技能；12.1 奥法例外与 M5 共用真实移动安全判断，所以静止时不会再次过滤
自有源选出的奥冲或飞弹。各专精状态、法术 ID 与开场计数均在独立文件中，不通过
共享运行时传播职业规则。

## 完全脱离 JustAC

把 TOC 中 JustAC 设为可选依赖后，完整独立源至少应按需实现：

- `GetQueue()`
- `GetSpellHotkey(spellID)`
- `GetItemHotkey(itemID)`
- `GetDisplaySpellID(spellID)`
- `GetEffectiveSpellID(spellID)`（推荐；先解析动态动作栏形态，再解析天赋替换）
- `IsSpellUsable(spellID)`
- `IsSpellOnCooldown(spellID)`（真实技能冷却，必须排除公共 GCD；未知返回 `nil`）
- `IsSpellCooldownRemainingAbove(spellID, seconds)`（DurationObject 阈值比较；不读取
  secret 剩余秒数，无法证明时返回 `nil`）
- `IsSpellProcced(spellID)`
- `IsChanneled(spellID)`
- `IsConfirmedOutOfRange(spellID)`
- `IsTargetWithin(yards)`

其余可选能力：

- `IsBurstCue(spellID)`（仅标记当前源已明确判定应执行的爆发提示）
- `GetHighlightCastSpell()`
- `GetDetectedBurstTriggers()`
- `GetEngagedEnemyCount()`
- `IsTargetBoss()`

所有方法都是无 `self` 的普通函数。Bridge 对调用使用 `pcall`；未知或 secret
状态遵循现有 fail-open/fail-closed 策略。自定义源未实现 `GetEffectiveSpellID`
时会回退到 `GetDisplaySpellID`，因此旧源保持兼容。
