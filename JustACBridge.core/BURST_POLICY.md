# DK / 法师双动作策略

## 目标

- **主推荐**：执行当前推荐源的自有队列；源可先做条件完整且可实时证明的精确判断，
  无法判断更高优先级条件时再原样回退 JustAC。随后执行推荐源通过
  `IsBurstCue` 明确标记的爆发提示（JustAC Stage G 为保留 Blizzard 第一推荐可能将
  它放在第 2 位），随后才处理维护技能和普通第一推荐。精确提示只允许表达一个已验证
  的窄条件，不得冒充完整 APL；提示仍须通过安全、可用和快捷键检查。
- **保留爆发版**：面向拉怪跑路和普通 Boss 机制持续按住。火法、冰法、冰 DK、邪 DK
  的内置 12.1 源通过 `GetPreserveQueue()` 从原始 JustAC 队列选择。12.1 奥法是唯一
  例外：M4 使用与 M5 相同的 `arcane121` 自有普通优先级，只跳过奥术涌动和
  大法师之触，且不合并 JustAC 的其他 Burst Trigger。所有专精随后都只取非保留、
  当前可用、已绑定且可移动安全的动作；
  即使当前一帧静止，也不启动不可移动读条、引导或蓄力。
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

## 法师

当前规则依据：

- Midnight 12.0 改动：https://worldofwarcraft.blizzard.com/en-us/news/24244455
- Midnight 12.1 职业改动：https://www.wowhead.com/news/new-prismatic-bolt-ability-and-improved-defensives-arcane-mage-class-changes-and-382132
- 12.1 S2 当前 SimC APL：https://github.com/simulationcraft/simc/blob/midnight/ActionPriorityLists/default/mage_arcane.simc
- 12.1 奥法循环（2026-08-14 更新）：https://www.wowhead.com/guide/classes/mage/arcane/rotation-cooldowns-pve-dps
- 12.1 火法/冰法当前 SimC APL：https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/apl/mage.cpp
- 12.1 冰法循环：https://bbs.nga.cn/read.php?tid=47313033
- 12.1 火法循环：https://bbs.nga.cn/read.php?tid=47171968

历史 11.2 兼容依据：

- 冰法：https://bbs.nga.cn/read.php?tid=44557448
- 火法：https://bbs.nga.cn/read.php?tid=44566937
- 奥法：https://bbs.nga.cn/read.php?tid=44714113
- 日怒奥后置触：https://bbs.nga.cn/read.php?tid=44942797
- 饰品：https://bbs.nga.cn/read.php?tid=44724336
- 属性：https://bbs.nga.cn/read.php?tid=44765732

默认保留：

| 专精 | 默认保留法术 |
| --- | --- |
| 奥术 | 奥术涌动 `365350`、大法师之触 `321507` |
| 火焰 | 燃烧 `190319`、流星 `153561` |
| 冰霜 | 冰冷血脉 `12472` |

保留版额外排除：

- 火法：烈焰风暴 `2120`（地面选点）。
- 冰法：寒冰宝珠 `84714`、冰霜射线 `205021`、暴风雪 `190356`、冰锥术 `120`。
  前两项只允许 M5 释放，后两项避免 M4 猜测地面位置或人物面向。

两篇 NGA 奥法文章描述的是 **TWW S3 / 11.2**。其后置触结论依赖当时的四件套、
共鸣、敏锐直觉、白炽耀焰和奥术之魂轴；11.2 策略仍保留完整的
涌动 `365350` / 唤醒 `12051` / 触 `321507` 爆发组，以及奥术飞弹 `5143`
一个 GCD 后主动截断。

**Midnight 12.0 起不再沿用该 APL。** 12.0 已移除或重做敏锐直觉、祥和、
虚空精准、白炽耀焰等旧联动，并让唤醒不再提供节能施法或叠层智力增益。因此当前保留版只
扣住奥术涌动和大法师之触；唤醒作为缺蓝时的恢复技能正常通过。策略字段
`reservePassthrough` 会在合并 JustAC Burst Trigger 后再次移除唤醒，避免旧配置
把它错误扣住；玩家仍可用 `/jacb reserve add 12051` 主动改回保留。

12.1 奥法进一步把默认保留集固定为涌动与触，不读取 JustAC Burst Trigger 中的
其他法术，防止旧配置把宝珠、弹幕等普通动作一并扣住。`/jacb reserve` 玩家覆盖
仍在最后应用，因此明确的个人配置不受限制。

12.0 的奥术飞弹不再全局强制在一个 GCD 后截断，恢复普通完整引导。

奥术宝珠 `153626` / 覆盖形态 `153640` 按人物面向发射，而副本内无法可靠取得目标
方位并控制人物转向。12.1 的 M4/M5 在移动中都会排除宝珠，避免处理机制时向错误
方向发射或额外拉怪；停止移动并连续静止满 2 秒后两者才恢复。两秒内再次移动会
重新计时，确保玩家有时间调整面向。11.2 的 M4 仍维持历史上的永久排除规则。

奥法不登记人为最终兜底。12.1 S2 的当前 SimC 疾咒师/日怒 APL、主流攻略优先级及
JustAC 自带 `MAGE_1` SimC 队列均不包含魔爆术 `1449`；因此 12.1 规则从 M5/M4
两路自动动作排除它。原队列没有其他合格动作时保持空动作，不为了避免空输出而
擅自选择填充技能。手动释放魔爆术不受影响；旧版本仍只从 M4 持续按住动作排除。

12.1 的奥术脉冲 `1241462` 天赋替换魔爆术按钮，棱彩箭 `1295939` 则会动态替换
奥术冲击。推荐源可能返回基础按钮 ID，而实际技能已经变化；Bridge 因此先解析
动态动作栏形态，再解析天赋替换，并对外导出实际技能 ID。魔爆术的排除只匹配解析
后的实际 `1449`，不会误伤奥术脉冲；棱彩箭也按自身零读条形态参与 M4 移动安全
判断，不会被基础奥冲的读条时间错误挡住。Windows M5 因而也不会把奥术脉冲误当
魔爆术套用 `100ms` 观察窗口。

当前可取得的敌人数只是“有玩家仇恨关系的可见姓名板数”，既不是玩家身边精确数量，
也不能证明敌人处于奥术脉冲的目标落点范围。12.1 的两套英雄天赋又使用不同目标阈值，
因此 Bridge 不用该近似值重写奥法单体/AOE 分支，动态优先级继续交给推荐源。

12.1 攻略区分普通与 `Overpowered Missiles` `1277009` 强化飞弹：普通飞弹建议
在下个技能可排队时截断，强化飞弹必须完整引导。但当前实战日志没有足够样本证明
WoW 能让 Bridge 在增益被消耗前稳定读取并绑定到本次引导。按照“不能可靠判断就
不主动截断”的保守原则，12.1 将奥术飞弹登记为 `protectedChannels`，所有飞弹
完整引导。只有已有明确旧版本依据的 11.2 继续使用 `clipChannels`。
这项条件移动施法只属于 M5；M4 的持续按住契约始终跳过所有引导，不会主动启动飞弹。

霜火冰在明确超过 20 码、已学霜火之箭且 JustAC 当前给出“冰川尖刺→冰风暴”时，
会从原队列提前选择已绑定且可用的冰风暴，避免套装火球失去碎冰。无法确认距离时
保持原顺序，不根据猜测改技能。

冰霜射线登记在 `protectedChannels`，必须完整引导。即使 WoW 在引导期间反复发出
移动事件，Bridge 也会继续保护该引导，不会因为持续按住 M4/M5 而在 GCD 结束时
发送冰风暴、冰枪术等下一技能将其提前截断。只有玩家自行移动或主动取消才会中断。

法师移动兜底只在原队列没有安全动作时启用：火焰用灼烧 `2948`、冰霜用冰枪术
`30455`；奥术没有人为兜底。这些兜底仍需通过已学习、可用、射程和快捷键检查。

奥法棱彩屏障 `235450` 会占用伤害 GCD，不能称为“无损维护”，因此已从 M5/M4 自动
动作移除，交给玩家按机制手动释放。冰法寒冰护体 `11426` 仍保留额外充能维护：只有
Buff 明确不存在、法术已学习、当前充能数明确大于 `1` 且快捷键已绑定时才自动释放，
始终留下 `1` 层供手动应对机制。

12.1 奥法 M5 改由 `Sources/Arcane121.lua` 自有源决策，不再用策略层给 JustAC 队列
打补丁。当前已验证切片包括：日怒战前涌动、疾咒师每场首个宝珠、辉光不存在或
至少两层时的涌动、涌动窗内前一 GCD 为棱彩箭/弹幕时的大法师之触，以及日怒节能
飞弹且奥术齐射低于 12 层。Liquid Luster `1295132` 的成功使用由玩家施法事件记录；
药水后的秘密层数、持续时间分支、齐射动态优先级等任一更高条件无法证明时，源立即
返回原始 JustAC 队列并在日志写出 `SOURCE_DECISION ... fallback=true`。这仍是可验证
切片加精确回退，不宣称已经复刻完整 SimC APL。

12.1 火法、冰法也分别由 `Sources/Fire121.lua`、`Sources/FrostMage121.lua` 独立决策：

- 火法区分炎爆术瞬发 Hot Streak/Hyperthermia 与 Pyroclasm 读条形态，三目标且已学
  Fuel the Fire 才切烈焰风暴；实现 Firestarter 保留、可观测燃烧窗、日怒燃烧内流星、
  Heating Up 空闲帧火冲和 Heat Shimmer/Scald 灼烧。燃烧前置读条由成功施法事件确认，
  随后在首个空闲帧发送燃烧，以保留仍在飞行的弹道；Bridge 在任意读条期间禁止持续
  按键注入，因此仍不伪造“读条结束前约 150ms 燃烧/火冲”的双法术编织。
- 冰法按服务器确认的施法事件推进霜火/疾咒师开场，覆盖冰川尖刺、彗星风暴、
  脑部冻结、寒冰指、宝珠、暴风雪阈值、Freezing 层数与英雄天赋分支。冰霜射线总是
  完整引导；SimC 的按射线跳数截断、不可可靠读取的冰刺数，以及秘密的套装时序均回退
  JustAC，不用固定时间近似。

两者都先保留原队列中的物品头部，让 JustAC 继续决定饰品/药水时序；M4 永远不用
自有队列，移动时仍由策略层跳过所有不可移动读条、引导和蓄力。

专精登记的最终兜底法术不参与失败熔断。它已经是没有更安全动作时的最后选择，
即使游戏返回施法失败，也不会累计失败次数或将该兜底临时屏蔽。

已登记最终兜底的专精会为 M4/M5 提供非空保证：正常队列选不出动作时尝试专精兜底
快捷键；M4 仍要求兜底本身可移动施放。射程和运行时 `usable` 结果只写入诊断日志，
不再把合格兜底过滤成空动作。奥法未登记兜底，因此允许输出为空。

普通推荐除 JustAC 的 `IsSpellUsable` 外还检查实际冷却/充能剩余时间。JustAC
队列短暂滞留在刚释放、仍处于冷却的冰风暴等技能时，Bridge 会立即跳过该条目，
避免 Windows 反复发送同一个必定失败的快捷键，并最终落到冰枪术兜底。

## 死亡骑士

Bridge 首先合并 JustAC 当前专精 `Burst Trigger` 配置，因此会自动跟随 JustAC
版本和玩家在 JustAC 中的覆盖设置。内置表作为兼容补充：

12.0/12.0.5 参考：

- 鲜血：https://bbs.nga.cn/read.php?tid=46185998
- 冰霜：https://bbs.nga.cn/read.php?tid=46299450
- 邪恶进阶：https://bbs.nga.cn/read.php?tid=46664305&_ff=320
- 邪恶天赋：https://bbs.nga.cn/read.php?tid=46271972
- 邪恶入门：https://bbs.nga.cn/read.php?tid=46372736

12.1 冰霜参考：

- Method 总览：https://www.method.gg/guides/frost-death-knight
- Method 天赋：https://www.method.gg/guides/frost-death-knight/talents
- Method 手法与循环：https://www.method.gg/guides/frost-death-knight/playstyle-and-rotation
- 湮灭削弱讨论：https://us.forums.blizzard.com/en/wow/t/121-frost-obliterate-25-nerf-what/2321138
- 12.1 当前冰/邪 DK SimC APL：https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/apl/apl_death_knight.cpp

| 专精 | 默认保留法术 |
| --- | --- |
| 鲜血 | 符文刃舞 `49028`、白骨风暴 `194844` |
| 冰霜 | 冰霜之柱 `51271`、冰龙吐息基础/当前覆盖 `152279`/`1249658`、符文武器增效 `47568`、冰霜巨龙之怒 `279302`、死神印记 `439843` |
| 邪恶 | 黑暗突变基础/当前覆盖 `63560`/`1233448`、亡者大军 `42650`、天启兼容 ID `275699`/`220143`、邪恶突袭 `207289`、召唤石像鬼 `49206`、培育憎恶 `288853`、邪恶蔓延 `390279`、腐化 `1247378`、灵魂收割 `343294` |

保留版不会扣住普通符文/符能消耗技能；它从 JustAC 队列继续选择可用填充技能，
避免把 Bridge 变成第二套、容易过期的 DK APL。

12.1 冰/邪 DK 分别由 `Sources/FrostDK121.lua`、`Sources/UnholyDK121.lua` 决策。
冰 DK 已实现可证明的冰柱/吐息资源门槛、死神印记窗口、冰龙之怒增益门槛、白霜、
杀戮机器双层/符文门槛、Razorice/Frostbane/Shattering Blade 与单体/AOE 消耗分支。
吐息/死神使者的精确冷却剩余和资源池无法从布尔冷却证明时，立即回退 JustAC。

邪 DK 已实现疾病高优先级兜底、成功施法确认真实 Festering Scythe 覆盖形态后才放大军、黑暗突变、
腐化、AOE 灵魂收割、Sudden Doom、Lesser Ghoul，以及当前 SimC 的传染阈值（无
Forbidden Knowledge 为 4+，有则 6+）。Cycle of Death 场地时序、Festering Scythe
剩余战斗时间、Army 精确冷却剩余、宠物存活和隐藏增益计时无法完整证明时回退 JustAC。
这些仍是“完整可观测切片 + 原队列兜底”，不宣称为脱离运行时信息的完整 APL。

M4 另外排除冰 DK 冰川突进 `194913`、冰霜镰刀 `207230` 和邪 DK 枯萎凋零 `43265`，
不猜测人物面向或绿色选点位置；这些技能仍可由 M5/玩家手动瞄准。

死亡之握 `49576` 仅属于控场/位移工具，不属于伤害优先级；冰霜策略将其登记在
`rotationExclusions`，即使推荐队列或突进模块误注入，也会在 M5/M4 两路同时跳过。

DK 移动兜底：鲜血依次尝试血液沸腾 `50842`、死神的抚摸 `195292`，不擅自消耗
本应用于灵界打击的符能；冰霜优先白霜触发的凛风冲击 `49184`，无触发但仍无安全
队列动作时也用凛风冲击作为远程符文填充；邪恶在 5 个及以上交战目标时优先传染
`207317`，否则使用凋零缠绕 `47541`。兜底不使用任何保留爆发技能。

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
- 12.1 奥法只有在浮光掠影 `236457` 已学习且节能施法 `263725` 光环存在时，才把
  奥术飞弹 `5143` 视为可移动引导；气定神闲 `205025` 光环存在时，才把奥术冲击
  `30451` 视为移动安全的瞬发。任一 API 状态未知都会保守跳过；
- 冰川尖刺的旧版/当前覆盖 ID `199786`/`1236209` 登记为移动时强制跳过，
  优先级高于覆盖按钮的 Proc 高亮及移动施法例外；
- 寒冰箭、霜火替换形态及暴风雪 `116`/`431044`/`468655`/`190356` 不使用
  推荐高亮或浮冰推断瞬发；只有当前有效法术形态被 API 明确报告为零读条时，
  才允许移动施放；
- 无法确认是否可移动施放时保守跳过，不向动作队列发送该技能。
- 只有原队列前 8 项全部没有安全、可用且已绑定动作时才进入职业兜底；M5/M4
  共用兜底数据，M4 额外要求动作可移动施放，并排除爆发、药水和主动饰品。
- 若移动中某个当前推荐在 300 ms 内连续被游戏拒绝 3 次，则短暂跳过该动作并
  继续扫描；没有其他可执行项时进入专精兜底，避免永久重复一个实际无法释放的技能。
- 战斗中速度属于受保护数据时，以移动事件为准；同帧开始/停止事件会防抖，移动
  意图可以打断本就无法移动维持的引导，不会让 M4/M5 永久停在引导保护。

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
