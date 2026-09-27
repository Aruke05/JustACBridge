# 前置动作与成功事件序列

新增“准备好 B 后，先 A 再 B”时，优先使用 `ActionSequence.lua`，不要复制职业状态机，
也不要先输出 B，再试图在施法后补救 A。机制默认不对任何专精启用；目前冰 DK 12.1
策略接入，奥法既有配对规则保持原实现，不借重构改变其他职业 APL。

## 两层职责

- **专精策略**：声明技能 ID、别名、适用构筑、资源门槛、可观测冷却、等待时允许的
  原队列动作、失败策略和明确的取消条件。先核对当前指南，不能从别的职业照搬条件。
- **通用机制**：三态归属/绑定证据、前置条件 `ready / wait / skip`、保序删除、
  成功事件推进、同目标凭据、别名、超时和实例隔离。不猜测资源恢复或冷却剩余。

策略通过 `selectLossless(queue, context)` 在 M5 普通选择之前接入；使用
`context.inspect(id)` 获取独立的 `known/bound` 三态，补充本策略可证明的
`ready/usable/noPower` 后调用 `Prerequisite`。`context.canUse` 的布尔结果只适合
“能否注入”资格门，不能用于判断可选前置是否缺席。旧的事后 `prepareLossless` 钩子已移除。

## 不可违反的契约

1. `false` 表示明确否定，`nil/secret/异常` 表示未知。归属可由 `IsPlayerSpell` 或
   `IsSpellKnown` 正面证明；不能用可用、高亮、队列存在或成功历史替代。
2. `GetSpellHotkey` 非空字符串是绑定、空字符串是明确未绑定；nil/接口缺失/抛错是
   未知。适配层不能用 `or ""` 把未知变成可跳过前置的凭据。
3. `Prerequisite` 只有明确未学习或未绑定才返回 `skip`。已学习且绑定，但冷却中、
   缺资源、不可用或状态未知均返回 `wait`。冷却是本体/GCD/符文冷却哪一种未被证明时，
   尤其不能用“非就绪”推导“这一步可以省略”。
4. `New` 的 `steps` 声明顺序。先调用 `Check(context)`，再按最新状态判断资源和就绪。
   `Propose` 不算成功；`Observe` 只接受玩家成功事件推进。`Propose` 不允许跳过前置，
   除非该步骤显式 `optional=true` 且逐项提供当前正面缺席证据。缺席证据不缓存。
5. 建议顺序示例：`{A optional, B windowAnchor, C}`。A 可用时 `Propose(1, context)`；
   A 成功后 `step==2` 才能推荐 B。A 明确缺席时，才可
   `Propose(2, context, reason, {[1]=evidenceForA})`。A 暂不可用必须等待，而不是走这条分支。
6. 等待可返回 `Filter` 过滤后的当前原队列，或权威的空队列；核心不能在空队列之后
   偷跑普通 fallback、维护、burst cue 或高亮注入。过滤保持其余动作原相对顺序。
7. 提案只保留有限时间的同目标“候选凭据”，不缓存可用性。冷却先更新、成功事件后到，
   应等待事件而不是自动跳步。失败策略由配置显式选择；按住键产生的 GCD 失败不等于成功。
8. 目标变化/失效、脱战、进世界、专精和天赋切换必须调用 `Reset`。有光环窗口依赖时
   配置 `windowAnchor` 与可靠的期限，超时取消；不能猜测持续时间延长。
9. 任何建议仍要经过公共核心的学习、快捷键、距离、移动、读条/引导安全判断。
   通用机制不能绕过这些检查；M4 与 M5 的接入必须由专精显式决定。
10. `Describe(evidence)` 必须随前置等待/跳过日志输出。不能只记一个 `NO_A`，丢掉
    `known / bound / ready / usable / noPower` 的真实判定区别。

## 新职业接入清单

- 至少测：前置明确可放、冷却中、缺资源、明确未学/未绑、nil/secret/异常；普通队列
  把后继放队首甚至完全不含前置时，仍然不能越过前置。
- 重复推荐不推进；成功才推进；GCD/资源失败、别名、冷却先到、换目标后切回、失效、
  超时、手动乱序、重置与两个实例互不影响。
- 过滤后空队列不能被核心兜底绕过；M4/M5、移动及引导保护都要做核心集成测试。
- 跑 `ActionSequence.test.lua`、目标策略定向测试、全量回归和 TOC 加载顺序检查；
  安装前备份，安装后逐文件校验。离线 mock 不等于已证明真实客户端 API/事件时序。

## 提前准备资源：ResourcePreparation.lua

`ActionSequence` 只管理成功事件顺序；提前准备使用独立、无状态的
`JustACBridgeResourcePreparation`，不要在其他职业复制冰 DK 的技能表或倒计时锁存。

- `CooldownBelow(id, seconds, query)`：读取新鲜、排除 GCD 的 DurationObject，默认
  RealTime 秒数；严格小于阈值才为 true，等于 6 秒时尚不进入 6 秒内准备。
- `ResourceAtLeast(unit, powerType, threshold, query)`：使用当前真实资源上限，不能
  假定满条必为 100。明文资源精确比较；隐藏数值交给原生引擎曲线，Lua 不比较 secret。
- 引擎曲线固定为 Step 的 0/100 二值阶梯。首次建立必须通过原生 `Evaluate` 的阈值前、
  正好阈值、阈值后和两端自检；自检失败不得退化成线性斜坡或百分比取整。只缓存最多
  64 个不可变曲线，不缓存冷却、资源、消耗或判定结果。未知上限不能猜百分比。
- `FixedCost(id, powerType)`：实时读取当前有效技能的消耗。只支持明确的固定资源消耗；
  缺行、secret、条件光环、百分比、持续消耗或可变消耗均为未知，不当免费技能。
- `Filter(queue, context, config)`：策略显式提供 `blocked/spenders/powerType/reserve/reason`。
  只删除爆发技能和无法证明“花费后仍留够 reserve”的耗能技能，保留原队列相对顺序；
  不注入回能技能，不根据推荐/成功事件猜测资源增加。空队列具有权威性。
- `query("ReadBinaryPredicate", value)` 只接收上述经过自检的二值结果，返回
  `调用成功, true/false/nil`。JustAC 适配层使用它现有的 secret-safe 布尔桥，未知保留 nil。
  禁止把原始资源/秒数传入该桥，其底层整数转换不适用于原始数值。

策略必须先证明当前窗口即将到来、技能已学且已绑、有效形态正确、前置没有错开，才调用
过滤。窗口未知或不满足时不建立准备锁；下一帧重新判定并保留原推荐。已经正面证明近窗，
但某个耗能技能的消耗或剩余资源未知时，保守扣住该耗能技能，不声称完全避免溢出。

当前只有冰 DK 12.1 M5 显式接入；M4 以及其他职业不变。6 秒是用户选择的有限准备窗口，
不是指南提供的普适最优阈值。不同职业必须独立研究资源/充能/消耗类型，不能用本模块的
单冷却 DurationObject 判断多充能技能是否还有可用层数。

新接入至少覆盖：阈值两侧/相等、消耗变化、不同资源上限、secret/nil/异常、错误曲线
自检失败、空队列不被兜底绕过、普通小窗口、准备→四连的核心集成、原队列保序及模式隔离。
参考 `ResourcePreparation.test.lua` 的双配置隔离与 `CoreIntegration.test.lua` 的隐藏值端到端测试。

## 目标身份与有效性：TargetLease.lua（2.13.8）

不得把“GUID 不可读”当成“没有目标”，也不得为此缓存/伪造 GUID。原有
`getCurrentHostileTargetGUID` 保持严格，仅适合明确要求可读 GUID 的机制，例如奥法触。

需要在受限制场景跟踪当前选中目标的策略可显式配置
`selectionTargetScope = "target-epoch"`，当前仅冰 DK 12.1 启用：

- `TargetLease:Read()` 每次读取 exists、attackable、dead；只有明确存在、可攻击、
  存活才允许动作。GUID 只是额外的可读身份变化检查，不是启动门槛。
- `targetKey` 是当前目标选择周期内的本地对象，不是 GUID 或“上次已知目标”的替身。
  `PLAYER_TARGET_CHANGED` 是客户端同步事件，核心立即清除周期和序列；切回旧目标
  必须重新开始。进世界、脱战、切专精/天赋也清除；每次明确死亡/友善/不存在都清除。
  可读 GUID 不一致提供额外清除证据。周期不负责延长序列既有的 10 秒期限。
- 有效性未知时不能给出施法许可。冰 DK 返回权威 `WAIT_TARGET_EVIDENCE` 过滤队列，
  扣住四连与耗符能动作，只保留原顺序的普通回能动作；空队列不能被兜底绕过。
- 已建立周期内的未知有效性不等于换目标：暂停推荐但保留短期施法收据，只有真实玩家
  成功事件可推进，恢复推荐仍必须重新取得当前有效性。无周期时未知不能创建周期。
  `UNIT_HEALTH/UNIT_FLAGS` 不能仅因 GUID 隐藏而擦掉正在进行的冰 DK 收据；其他
  GUID-bound 规则仍照旧清理。明确失效仍立即清除全部凭据。
- `targetEvidence` 分开记录每项 true/false/secret/missing/error/unknown；不输出秘密
  值，不再把缺目标、超距和身份不可读混成一个原因。这里只消除多余身份限制，不
  承诺客户端隐藏所有有效性接口时仍能自动爆发。

API 依据：客户端生成的 [Unit API / PLAYER_TARGET_CHANGED 同步事件定义](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)。
定向测试先重现旧版在 hidden GUID 下输出冰柱而非回能，再验证四连、隐藏资源/冷却、
健康事件、未知等待、换目标/切回、重置与奥法不外溢；禁止把这里的 epoch 直接用作
跨目标 DoT 归属、历史目标查找或奥法同 GUID 规则的替代品。

## 本次修复的边界

2.13.5 实际记录是冰柱 10357.431 → 吐息 10357.680 → 龙怒 10357.894 → 印记 10359.478，
开柱前原因为 `EXPECT_PILLAR_NO_MARK`。旧日志没有记录分支中的归属/冷却证据，不能
断言是某个 API 的具体故障。本次修复覆盖所有可导致旧分支误放行的未知/临时不可用
路径，并增加逐项诊断。确实把印记 CD 手动打乱时，大窗口会等已学习且绑定的印记，
这是用户指定的严格前置，不宣称适用于所有战斗的最高 DPS 决策。

## 互斥分组及失败封闭（2.13.10）

职业声明多种 `ActionSequence` 形状，共享机制管理各自成功凭据；策略每帧按当前
精确证据选择形状，不得以另一实例的成功或单个技能 CD 猜测完成。冰 DK 12.1
使用必需的印记→冰柱和印记→冰柱→吐息→首次龙怒，只有两龙都 >18 秒才开小组；
任一已好/≤18 秒/未知都等待大组。已成功启动的小组不在中途追加龙喷步骤。

`losslessSelectionFallbackBlock` 声明仅归序列所有的动作 ID。核心在 selector
nil、异常或缺失时构造保序过滤队列；选择器返回的普通队列也再过滤一次，防止任何
普通 cue/维护/兜底重引入。`losslessSelectionPassthrough` 仅按当前明确的有效 ID
放行独立动作（本专精的召回），不能放行该帧其他组内技能。两项只对配置版本的 M5
生效。`allowCastFollowup=true` 可显式保留现有非组内成功跟随；候选仍经核心合法性
和组内屏蔽检查，不能借此重引入被保留动作。空队列仍具有权威性。

`ResourcePreparation.CooldownAbove` 提供严格大于比较：明文直接比较；隐藏值用
next-double 阶梯并自检边界两侧。若原生精度不足，仅在整数上界阶梯能正面证明更大
时返回 true，不可判定区间返回 nil。例如 >18 的隐藏 [18,19) 可能保守等待，≥19
才有充分证据；不缓存上帧答案，不比较秘密数值。此处不确定性必须在日志和报告保留。
不能因此把 18 秒等组变成 18 秒憋资源；准备仍由职业独立的 6 秒近窗谓词控制。

## 离散资源准备与多资源组合（2.13.11）

`ReadySlotsAtLeast(slotCount, threshold, readReady, query)` 每次重新读取每个槽位；
仅计当前正面就绪，部分未知时只使用可证明的上下界，不猜正在恢复的槽位何时完成。
隐藏布尔交给原生 `C_CurveUtil.EvaluateColorValueFromBoolean(value, 1, 0)`；先验证
true→1、false→0，才把结果交给已有二值适配器。不能把原始数值或未验证曲线当作
0/1 判定。接口缺失/异常/自检失败仍返回未知，无任何跨帧资源缓存或 UI 条状态读取。

`Filter` 可显式配置 `resourceAtLeast(threshold)` 来接入该资源判定，不复制队列
过滤器；`integerCosts=true` 拒绝离散资源的非整数消耗。`allowFree=true` 只放行当前
API 明确返回固定 0 消耗的已列举动作，不把缺行/nil/异常当作免费，不根据高亮猜 proc。
未列入职业消费表的动作保持原源顺序；这是局部资源保护，不是完整 APL。

冰 DK 的配置读取印记当前符文成本，准备范围沿用严格 <6 秒。小组要求两龙都 >18 秒；
否则必须证明整个大组均在近窗，不能在等待两龙期间提前囤符文。Rune reader 使用
当前 `GetRuneCooldown(index)` 的第三返回值，6 个槽位是职业配置而非公共层假设；
不使用语义未验证的 `UnitPower(5)`，也不调用 JustAC 的事件驱动 UI 条计数。

大组先执行原有 RP 保留，再对剩余原队列施加符文保留，确保两条件同时满足。原来的
印记缺资源全停分支，只有当前完整准备条件被证明时才改为保序过滤：小组可继续泄符能，
大组花费后仍需留下 60。回能技能仅在原队列中放行，不因其推荐/成功就提前解锁。
印记玩家成功事件后立刻解除符文保留；目标/窗口/模式变化每帧重算，无准备状态锁存。

依据：客户端 [RuneFrame 当前就绪读取](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_UnitFrame/Mainline/RuneFrame.lua)、
[原生布尔求值接口](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua)、
[当前技能消耗结构](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua)。
离线测试验证 0–6 个符文、动态成本、免费触发、secret/nil/异常、6 秒边界、大小组与
双资源门、空队列、成功事件解除、重置、核心实际导出及 M4 隔离；实际客户端隐藏
接口/成本结构可能不可用，未知会保守等待，不能宣称实战无损或不会暂停。

## 按步骤到期的启动门（2.13.12）

`State:CanStartCooldowns(ready, within, gcd, startDelay)` 只做当前帧启动判断，不保存
CD/资源预测，不推进序列。第一步必须当前已好；后继可以已好，或者由 `within(id, seconds)`
正面证明在轮到它时转好。`startDelay` 仅可来自当前真实 GCD 剩余时间，未知用零额外信用。
`steps[].gcdAfter` 显式声明该动作之后增加几个 GCD：不占 GCD 必须为 0，缺失表示未知，
不能默认每个按钮占一个。所有技能已好时不需要时间证据，不得因为优化接口缺失反而卡组。
单技能组没有后继时间门。读条/引导、特殊 GCD 或充能技能须另外证明，禁止套用本配置。

冰 DK 的已验证 APL 有 `reapers_mark` 在 `pillar_of_frost.remains<=gcd.max` 时起手的条件。
本用户严格分组仍保留：小组只检印记→冰柱；大组检查印记→冰柱→龙喷→龙怒。后面三个
共享印记贡献的一个 GCD，不给冰柱或龙喷额外加一个 GCD，也不套用 APL 的预计回能放宽
为 40 符能。两龙 >18 秒分组、6 秒资源准备和当前 60 符能要求均不变。

- `HastedGCD(1.5,0.75,GetHaste())` 是本策略的当前近战急速 GCD；不复用上个 GCD
  时长或旧急速。当前急速未知时仅用已知下限 0.75 秒的充分条件，不猜 1.5 秒。
- `QueueTiming.ReadGCDRemaining()` 精确读取当前 GCD 结束剩余量，非 1 的 rate、
  secret/nil/异常不提供额外信用。不改输入窗口/CVar，不提前发送受 GCD 保护的动作。
  这避免预输入末尾把“后继还差一个 GCD＋当前剩余 GCD”错误判为迟到而排入普通填充。
- `CooldownAtMost` 使用排除 GCD 的新鲜 DurationObject。边界为包含相等；处理时钟
  加减的 IEEE-double 四个 ULP 舍入界，且此修正严格小于 1 微秒，不添加任意延迟容差。
  hidden 数值仍走自检后的 Step 曲线；原生精度不足时严格早于期限是充分条件，仅无法
  分辨的边界保持未知，不把明显迟到放行。实际施放仍必须等当前引擎就绪，不用数值
  容差伪造就绪。
- 已成功开组，只检查当前步骤及未消费资源。后继处于获准的短 CD 时不得取消重开；
  衔接阶段的 CD/成功确认等待返回权威空队列，防止多插普通 GCD。资源确实不足仍走原有
  回能过滤。真实乱序、目标失效和原有 10 秒期限仍取消；这不是永远等待的锁。
- 日志 `START_TIMING` 记录每步 ready/by、当前 GCD 依据、起手偏移；缺证据/超时
  指向具体步骤。M4、其他职业与旧版本不启用该启动门，不能声称已改好所有职业。

依据（2026-09-27 核对）：[SimC Midnight 冰 DK APL](https://github.com/simulationcraft/simc/blob/midnight/ActionPriorityLists/default/deathknight_frost.simc)、
[SimC GCD 缩放](https://github.com/simulationcraft/simc/blob/midnight/engine/action/action.cpp)、
[客户端急速属性读取](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua)。
测试涵盖准入两侧/相等、非 GCD 不加时间、当前 GCD 末尾、多个急速下连续五轮、隐藏 CD
与资源和目标的核心导出、实际后继等待、资源不足、失败/成功先后、未知接口与模式隔离。
以上为离线 mock/核心集成验证，不能证明真实客户端所有 secret 接口与事件延迟均可用。

## M4/M5 模式与队列隔离（2.13.13）

`ResourcePreparation.IsEnabled(context)` 只接受明确的 `mode="lossless"`。核心为
`selectLossless` 显式提供该模式；直接调用公共资源过滤器的测试/新职业也必须声明。
`preserve`、缺失、secret 或无效模式都禁用爆发资源保留：`Filter` 只删除配置的爆发
blocked 项，不读花费/资源，不删除普通 spender。冰 DK 的启动入口也执行同一检查，
不能因为准备被禁用就绕过资源门提前开爆发；模式禁用只返回普通原队列，不推进/清除
另一路已有的 M5 成功凭据。

核心在调用另一源 getter/职业 selector 前，分别复制 M5 原始队列、M4 原始队列及
交给 selector 的数组。源复用数组或 selector 原地修改都不能污染另一路。存在爆发门
时，M4 不复用 M5 选择的普通回能动作，也不从原队列第 2 位起扫；必须从自己的第 1 项
按已有保留和合法性条件选择。未接入爆发门的专精保留原行为；独立 `GetPreserveQueue`
（包括奥法特例）仍具有权威性。

插件每帧同时计算两路，日志中的 `preparationReason` 属于 M5，现在注明
`preparationScope=M5`；它不是鼠标当前按键状态。实际比较需联合 QUEUE/PQUEUE、
`SELECT.preserve` 与成功事件，不能把 M5 空动作或 POOL 字样误当作 M4 等待。

这保证 Bridge 不为 M4 施加爆发资源准备，不承诺改变上游推荐源自己的 APL。源只给
回能动作而未给消耗动作时，M4 仍按原队列；不得强插冰打或前移后排 spender 来制造
“不攒能”的表象。定向测试包含各模式/资源接口不访问、切换无锁存、selector 注入/
过滤/空队列、普通专精公共复用路径、源共享数组、M4 原队列没有 spender 以及核心导出。
