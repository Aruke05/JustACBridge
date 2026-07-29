# DK / 法师双动作策略

## 目标

- **主推荐**：静止时逐帧透传当前推荐源的第一推荐；移动时跳过无法移动施放的
  读条、蓄力和引导，从原队列选择首个安全动作，不重写职业 APL。
- **保留爆发版**：仅当第一推荐属于保留项时，改用 JustAC 已经计算好的首个
  非保留、当前可用且已绑定动作；没有安全替代项时保持为空，不猜测技能。
- 不改变 `SpellQueue.GetCurrentSpellQueue()` 的调用频率，不增加定时等待。

## 维护边界

- 公共选择、版本匹配和玩家覆盖逻辑：`Policies/Registry.lua`
- 法师法术表：`Policies/Mage.lua`
- DK 法术表：`Policies/DeathKnight.lua`
- 推荐源注册与 JustAC 适配：`Sources/Registry.lua`、`Sources/JustAC.lua`
- 场地技能生命周期：`Trackers/GroundEffects.lua`
- `JustACBridge.lua` 只消费已解析策略，不包含职业法术 ID。

新增职业或为新 Interface 版本增加差异时，仅增加/修改对应策略文件及 TOC
加载项；现有 SavedVariables 仍按 `CLASSFILE_<专精序号>` 保存，不需要迁移。

## 法师（TWW S3 规则依据）

参考：

- 冰法：https://bbs.nga.cn/read.php?tid=44557448
- 火法：https://bbs.nga.cn/read.php?tid=44566937
- 奥法：https://bbs.nga.cn/read.php?tid=44714113
- 日怒奥后置触：https://bbs.nga.cn/read.php?tid=44942797
- 饰品：https://bbs.nga.cn/read.php?tid=44724336
- 属性：https://bbs.nga.cn/read.php?tid=44765732

默认保留：

| 专精 | 默认保留法术 |
| --- | --- |
| 奥术 | 奥术涌动 `365350`、唤醒 `12051`、大法师之触 `321507` |
| 火焰 | 燃烧 `190319` |
| 冰霜 | 冰冷血脉 `12472` |

保留版额外排除：

- **寒冰宝珠 `84714`**、**冰霜射线 `205021`**：只允许无损版释放，
  保留爆发版始终跳过。

有意不保留：

- **流星 `153561`**：S3 火法结论是不强求放进燃烧，应尽量卡 CD，只有燃烧
  剩余时间不足以等它落地时才延后。

日怒奥的后置触取决于目标数量、血量和战斗轴。Bridge 无法从 JustAC 两个动作
可靠重建这些条件，因此主推荐在非移动过滤时完全跟随 JustAC；保留版只负责扣住整个
涌动/唤醒/触序列，是否切换由玩家决定。

奥法攻略明确要求奥术飞弹（含以太协调覆盖形态）在一个 GCD 后主动截断。该技能
登记在 `clipChannels`：Bridge 仍识别其引导状态，但不再用整段引导保护占住输入，
而是复用 v3 GCD 门控，只在最后约 120 ms 发送 JustAC 的下一推荐。

霜火冰在明确超过 20 码、已学霜火之箭且 JustAC 当前给出“冰川尖刺→冰风暴”时，
会从原队列提前选择已绑定且可用的冰风暴，避免套装火球失去碎冰。无法确认距离时
保持原顺序，不根据猜测改技能。

## 死亡骑士

Bridge 首先合并 JustAC 当前专精 `Burst Trigger` 配置，因此会自动跟随 JustAC
版本和玩家在 JustAC 中的覆盖设置。内置表作为兼容补充：

TWW S3 参考：

- 冰霜：https://www.wowhead.com/guide/classes/death-knight/frost/war-within-season-3
- 邪恶：https://www.wowhead.com/guide/classes/death-knight/unholy/war-within-season-3
- 鲜血：https://www.wowhead.com/guide/classes/death-knight/blood/war-within-season-3

| 专精 | 默认保留法术 |
| --- | --- |
| 鲜血 | 符文刃舞 `49028` |
| 冰霜 | 冰霜之柱 `51271`、冰龙吐息基础/当前覆盖 `152279`/`1249658`、符文武器增效 `47568`、冰霜巨龙之怒 `279302`、死神印记 `439843` |
| 邪恶 | 黑暗突变基础/当前覆盖 `63560`/`1233448`、亡者大军 `42650`、天启兼容 ID `275699`/`220143`、邪恶突袭 `207289`、召唤石像鬼 `49206`、邪恶蔓延 `390279` |

保留版不会扣住普通符文/符能消耗技能；它从 JustAC 队列继续选择可用填充技能，
避免把 Bridge 变成第二套、容易过期的 DK APL。

## DK 场地技能到期

枯萎凋零 `43265` 与亵渎 `152280` 共享 `death-and-decay` 场地规则：

- 监听玩家自己的 `UNIT_SPELLCAST_SUCCEEDED`，仅在服务器确认实际放置后开始；
- 打开绿色选点圈但没有完成放置不会误计时；
- 默认持续 `10` 秒，再次成功施放会刷新 `placedAt/expiresAt`；
- 仍有效时跳过队列中的重复枯萎凋零/亵渎，并选择后续安全动作；
- `/jacb ground off` 只关闭重复过滤，倒计时和导出仍保留；
- `/jacb ground reset` 可处理取消、特殊 encounter 重置等异常情况。
- 到期默认显示两秒中央红字、播放 Raid Warning，并调用 WoW TTS 朗读技能结束；
  可分别用 `/jacb ground alert/sound/voice on|off` 控制，`/jacb ground test`
  可立即验证。

WoW 不提供可持久查询的场地对象句柄，因此追踪的是“成功放置时间 + 职业策略
持续时间”，不依赖目标坐标或伤害跳数；即使场内暂时没有敌人也不会提前丢失。

## 主动饰品和药水

JustAC 队列用负数表示物品。保留版默认跳过所有物品，避免自动消耗药水或主动
饰品；主推荐静止时仍完整执行第一推荐。

## 移动过滤

默认启用 `/jacb movement on`。玩家移动时：

- 基础瞬发技能和物品允许执行；
- JustAC `IsSpellProcced` 明确报告当前 Proc 的读条技能按瞬发处理；
- JustAC 的引导技能表同时覆盖普通引导和 Evoker 蓄力技能，默认跳过；
- 职业策略的 `moveCastAlways`、`moveCastBuffs` 可登记灼烧、浮冰一类例外；
- 冰川尖刺的旧版/当前覆盖 ID `199786`/`1236209` 登记为移动时强制跳过，
  优先级高于覆盖按钮的 Proc 高亮及移动施法例外；
- 无法确认是否可移动施放时保守跳过，不向动作队列发送该技能。

## 射程过滤

默认启用 `/jacb range on`。Bridge 复用 JustAC
`SpellQueue.IsConfirmedOutOfRange`，其底层读取
`C_Spell.IsSpellInRange(spellID, "target")`：

- 只有明确返回超出射程时才跳过，并继续扫描原 JustAC 队列；
- 自身技能、无目标技能、地面技能或 API 无法确认时保持原推荐；
- 近战技能离开 Boss 射程后可自动选择后续远程技能或突进技能；
- `/jacb range off` 可恢复不做射程过滤的行为。

## 玩家覆盖

覆盖按当前专精保存：

```text
/jacb reserve list
/jacb reserve add <法术ID>
/jacb reserve remove <法术ID>
/jacb reserve reset
```

`remove` 表示显式排除，即使该技能来自内置表或 JustAC Burst Trigger，也不会
再被保留。
