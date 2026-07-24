# DK / 法师双动作策略

## 目标

- **无损版**：逐帧透传 JustAC 当前第一推荐，不在 Bridge 中重写职业 APL。
- **保留爆发版**：仅当第一推荐属于保留项时，改用 JustAC 已经计算好的首个
  非保留、当前可用且已绑定动作；没有安全替代项时保持为空，不猜测技能。
- 不改变 `SpellQueue.GetCurrentSpellQueue()` 的调用频率，不增加定时等待。

## 维护边界

- 公共选择、版本匹配和玩家覆盖逻辑：`Policies/Registry.lua`
- 法师法术表：`Policies/Mage.lua`
- DK 法术表：`Policies/DeathKnight.lua`
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

有意不保留：

- **寒冰宝珠 `84714`**：S3 冰法结论是不再为冰脉刻意留球，应卡 CD 使用。
- **流星 `153561`**：S3 火法结论是不强求放进燃烧，应尽量卡 CD，只有燃烧
  剩余时间不足以等它落地时才延后。

日怒奥的后置触取决于目标数量、血量和战斗轴。Bridge 无法从 JustAC 两个动作
可靠重建这些条件，因此无损版完全跟随 JustAC；保留版只负责扣住整个
涌动/唤醒/触序列，是否切换由玩家决定。

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
| 冰霜 | 冰霜之柱 `51271`、冰龙吐息 `152279`、符文武器增效 `47568`、冰霜巨龙之怒 `279302`、死神印记 `439843` |
| 邪恶 | 黑暗突变 `63560`、亡者大军 `42650`、天启 `275699`、邪恶突袭 `207289`、召唤石像鬼 `49206`、邪恶蔓延 `390279` |

保留版不会扣住普通符文/符能消耗技能；它从 JustAC 队列继续选择可用填充技能，
避免把 Bridge 变成第二套、容易过期的 DK APL。

## 主动饰品和药水

JustAC 队列用负数表示物品。保留版默认跳过所有物品，避免自动消耗药水或主动
饰品；无损版仍完整执行第一推荐。

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
