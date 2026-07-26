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
/jacb source my-rotation
```

未实现的快捷键、射程、可用性、Proc、引导识别等能力会回退给已安装的 JustAC
适配器，因此替换推荐算法时无需复制动作栏扫描代码。

## 完全脱离 JustAC

把 TOC 中 JustAC 设为可选依赖后，完整独立源至少应按需实现：

- `GetQueue()`
- `GetSpellHotkey(spellID)`
- `GetItemHotkey(itemID)`
- `GetDisplaySpellID(spellID)`
- `IsSpellUsable(spellID)`
- `IsSpellProcced(spellID)`
- `IsChanneled(spellID)`
- `IsConfirmedOutOfRange(spellID)`
- `IsTargetWithin(yards)`

其余可选能力：

- `GetHighlightCastSpell()`
- `GetDetectedBurstTriggers()`
- `GetEngagedEnemyCount()`
- `IsTargetBoss()`

所有方法都是无 `self` 的普通函数。Bridge 对调用使用 `pcall`；未知或 secret
状态遵循现有 fail-open/fail-closed 策略。

