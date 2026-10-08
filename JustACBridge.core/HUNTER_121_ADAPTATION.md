# Hunter 12.1 适配说明

## 结论

12.1 的兽王、射击和生存猎均注册独立策略与自动推荐源。M5 只覆盖当前运行时能够完整
证明的 APL 切片；所有无法可靠判断的 secret、目标评分、剩余战斗时间、下一波时间、充能小数或
引导剩余 tick 分支都原样回退 JustAC。兽王的当前明文充能时序经过校验后可用于精确比较；
这不代表实际客户端中这些字段始终可读。M4 始终读取原始 JustAC 队列，只做本专精的
爆发保留、移动、引导、方向/地面与通用合法性过滤。

这不是把部分规则包装成完整 APL。`SOURCE_DECISION` 中出现 `fallback=true` 表示该帧
仍由 JustAC 保持原始优先级。

## 参考基线（猎人三系 2026-09-02；兽王 2026-10-08 再核验）

- SimulationCraft `midnight` 分支 Hunter APL：
  <https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/apl/apl_hunter.cpp>
  - 2026-09-02 的历史研究副本 SHA-256（不是本次兽王新基线的哈希）：
    `78A849051C05029DA054ED35F507C6ACDE1D7C67364088C79DCB7705D8A2F4D2`
- Method 12.1：
  - <https://www.method.gg/guides/beast-mastery-hunter/playstyle-and-rotation>
  - <https://www.method.gg/guides/marksmanship-hunter/playstyle-and-rotation>
  - <https://www.method.gg/guides/survival-hunter/playstyle-and-rotation>
- Icy Veins 12.1：
  - <https://www.icy-veins.com/wow/beast-mastery-hunter-pve-dps-guide>
  - <https://www.icy-veins.com/wow/marksmanship-hunter-pve-dps-rotation-cooldowns-abilities>
  - <https://www.icy-veins.com/wow/survival-hunter-pve-dps-guide>
- Wowhead 当前技能与专精说明用于核对技能 ID、施法形态、方向与引导属性。

源码优先级以当前 SimC APL 为精确顺序基线；攻略用于交叉确认打法意图。若攻略描述与
当前 APL/技能数据存在版本差异，Bridge 不猜测，保留 JustAC。

## 可观测性矩阵

| 条件 | 运行时证据 | 处理 |
| --- | --- | --- |
| 技能归属、可用、冷却开关 | `IsPlayerSpell`/`IsSpellKnown` + JustAC wrapper | 可用于自有动作 |
| 明确满充能 | `IsSpellAtMaxCharges` | 可证明 `full_recharge_time=0` |
| 普通光环/层数 | `GetAuraStackAtLeast` 返回 plain boolean | 可用于分支；nil 回退 |
| 敌人数 | JustAC 交战目标计数 | 单目标/低目标切表；未知回退 |
| 前一 GCD 成功施法 | `UNIT_SPELLCAST_SUCCEEDED` | 可证明兽王 BW 后补 Wild Thrash |
| 兽王 `full_recharge_time<gcd`、充能小数 | 当前原生层数、恢复起点/周期、`chargeModRate=1`、当前时间均为有效明文 | 精确计算全部缺失层数；secret、非单位速率、失效时序回退 |
| 其他猎人源充能小数 | 未接入上述兽王本地读法 | 仍保持原行为，不因本次改动外溢 |
| 兽王冷却剩余 `<gcd`/`>gcd` | 排除 GCD 的当前 DurationObject；当前急速决定 GCD | `<` 复用已自检的 ResourcePreparation；`>` 只接受精确明文秒数，未知回退 |
| `target_if`、优先目标、DungeonRoute 下一波 | 无可靠目标评分/路线时钟 | 原样回退 JustAC |
| `fight_remains`、`time_to_die` | 无可靠战斗时长 | 原样回退 JustAC |
| Rapid Fire `ticks_remain<2` | 无可靠剩余 tick | 不实现截断，完整保护引导 |
| 人物到目标方向/自动转向 | 副本内不可可靠取得并控制 | M4 排除前方锥形技能 |

## 三系行为

### 兽王 `bmhunter121`

- 自动识别 Pack Leader；Dark Ranger 的 Withering Fire 时长、Wailing Arrow 收尾和
  target 条件无法完整证明时交回 JustAC。
- 正面实现：单体怒火近窗的倒刺、倒刺即将满充能、怒火后的精确杀戮门、群体怒火/
  Wild Thrash 对齐与补 Beast Cleave，以及较高行均排除后的 Cobra Fang/普通填充。
- **不是固定连招**：每帧检查当前证据，不锁定“倒刺 → 杀戮”，不由怒火成功推算强化
  或充能。单体原 APL 可以在怒火就绪时连续消耗当前可用倒刺，不能擅改为只打一枪。
- 本次只覆盖 Pack Leader；Dark Ranger 原样交回 JustAC。
- M4 按用户配置始终保留 Bestial Wrath `19574` 和 Wild Thrash `1264355` / `1264359`；
  两者同时登记 `reserve` 与 `reserveExclusions`，已有取消保留覆盖也不能放行。
  Black Arrow、Barbed Shot、Kill Command 保持普通循环身份；M5 可继续使用 Wild Thrash。
- Wailing Arrow 强制按真实读条处理，不因按钮高亮被误判为移动瞬发。

#### 2.13.18 兽王决策边界

参考当前 SimC `beast_mastery` 正式分支，**不是** `beast_mastery_ptr`。
技能就绪还必须同时证明已学、已绑、可用且资源足够；高亮/正在恢复一层不替代这些证据。

| 当前情况（更高行必须先正面排除） | M5 行为 |
| --- | --- |
| 单体倒刺已满或全部充能恢复时间严格小于当前急速 GCD | 优先倒刺，防止充能损失 |
| 单体怒火本体冷却严格小于当前 GCD，倒刺可施放 | 先倒刺；下一帧重新读实际层数/冷却，不推算怒火返还 |
| 怒火已用，当前任一 Howl ready 光环明确存在，杀戮可施放 | 单体优先杀戮；没有 ready 光环不能拿召唤出的野兽/上次怒火当凭据 |
| 单体当前 Nature's Ally 明确存在 | 还须怒火剩余大于杀戮**全部**充能恢复时间加 GCD，并满足 Howl 冷却光环剩余 >4 秒或杀戮充能小数 >1.8，才优先杀戮 |
| 单体没有最终 Apex 天赋 | 保留 APL 的天赋例外，但仍查 Howl 的充能保留条件 |
| 单体没有杀戮放行依据 | 再检查 Cobra Fang 满层、Serpentine Strikes 或集中值 <75 等较低行，不机械连打杀戮 |
| 群体已点 Beast Cleave，Wild Thrash 可用，上一实际 GCD 是怒火或 Cleave 明确不存在 | 优先 Wild Thrash；上一 GCD 未知不能当成“不是怒火” |
| 群体怒火可用且更高行已排除 | 有 Cleave 时须 Wild Thrash 已好或本体冷却严格小于 GCD；明确未点相关天赋才应用原 APL 的缺席例外 |
| 群体 Nature's Ally 存在，或 Master Handler 且 >=4 目标/Howl ready，或无最终 Apex | Cleave 剩余严格大于 GCD 的 1/4（或明确未点 Cleave）时可优先杀戮；>=4 目标不强迫插一枪倒刺 |
| 多目标倒刺 `target_if` 行可能命中 | 原样交回 JustAC，不代替目标评分，不强行把杀戮移到倒刺前 |
| 必要字段 nil/secret/异常，或无法排除更高行 | 原样返回本帧 JustAC 队列及其相对顺序；不缓存上一帧结论 |

精确 Howl ready 对应三种当前光环 `471878` / `472324` / `472325` 的 OR；本次由 SimC
Hunter 模块创建 buff 与 `howl_summon.ready` 表达式联合核对，不外溢修改生存猎的旧实现。
Nature's Ally 当前光环为 `1276720`、最终天赋为 `1273126`；Master Handler 为 `424558`。
成功事件只记录真实上一 GCD，未知动作归属、换目标、脱战、进世界及天赋/专精切换清除凭据。
M4 完全不继承上述 M5 动态优先级，仍读原 JustAC 队列并执行既有保留/合法性过滤。

Cobra Fang 是兽王 12.1 S2 四件套效果。只有在该分支将被选中时，实时检查头、肩、胸、腿、
手五槽的实际装备，并按兽王专精 `253` 的套装奖励法术 `1296632` 正面计数；至少四件才
接管该套装动作。不按光环反推装备，不沿用上一帧/换装前件数。正面光环与不足四件的装备
证据冲突、或装备信息未知时原样回退；日志 `cobraSet=4pc/2pc/none/unknown/not-read`
区分当前分支的装备证据。四件正面证据已充分时，第五槽未知不影响四件套成立。
套装基线：[SimC 当前 set bonus 数据](https://github.com/simulationcraft/simc/blob/midnight/engine/dbc/generated/item_set_bonus.inc)。


### 射击 `mmhunter121`

- 自有源只覆盖单目标可证明行；多目标的 Trick Shots 时长、Spotter/Sentinel target_if
  与 12.1 套装 Explosive Shot 分摊交回 JustAC。
- Trueshot 的 `fight_remains`、Bullseye、Explosive Shot 对齐和下一波条件不可完整观测，
  只要 Trueshot 就绪便回退，不盲目按 CD 覆盖 JustAC。
- Explosive Shot 的 Tactical Reload/Unstable Trigger/DungeonRoute 分支不可完整证明时
  回退；Volley、Rapid Fire、Precise Shots 消费及终结填充只在更高行已正面排除时选择。
- Rapid Fire 可移动施放，但当前攻略/SimC 的末 tick 截断需要 `ticks_remain`；Bridge
  不能可靠读取，故完整保护到真实结束/中断事件。
- M4 保留 Trueshot，并排除需要地面放置的 Volley。

### 生存 `survivalhunter121`

- 直接读取不会 secret 的 Tip of the Spear 层数，并结合 Twin Fangs、Takedown 就绪/冷却、
  Wildfire Bomb 满充能与 Sentinel's Mark 实现低目标数的完整可证明行。
- `Takedown remains<gcd` 与 `Wildfire Bomb full_recharge_time<4` 只在“已经就绪/已经满充能”
  能正面证明时落地；其余回退。
- Pack Leader 的 `howl_summon.ready` 是内部驱动状态，不能拿可见 Howl 光环代替；只有
  后续同样确定选择 Kill Command 时才合并证明，否则原样回退 JustAC。
- 三目标及以上包含 Sentinel's Mark `target_if` 与正面锥形 Raptor Swipe，交回 JustAC
  保持目标和原始顺序。
- M4 保留 Takedown 与 Boomstick；Boomstick 和动态 Raptor Swipe 都从 M4 排除，交给
  M5/玩家面向。Boomstick 本身可移动引导；一旦由 M5 开始，完整保护三秒引导。

## 通用 Hunter 安全边界

自动伤害循环不发送 Disengage、Binding Shot、Counter Shot、Freezing Trap、Tar Trap、
Muzzle 或 Harpoon。它们分别涉及玩家位移、敌人控制/中断、地面选点或主动贴近，必须由
玩家按机制手动决定。

## 离线验证边界

纯 Lua 测试可证明注册、自动选源、plain/unknown 分支、队列顺序与策略字段；不能证明
实际 12.1 客户端中所有第三方 wrapper 的 secret 值、动态 override 事件顺序、快捷键与
具体副本目标几何。遇到这些边界时，设计结果是回退 JustAC 或空动作，而不是猜测。

## 本次兽王回归（2026-10-08）

- `Tests/BMHunter121.test.lua`：366 次决策断言及额外充能数学/成功事件/边界断言；包括
  怒火后倒刺与杀戮各 0/1/2 层、Nature/Howl、2/3/4 目标与 Master Handler 的组合。
- `Tests/CoreIntegration.test.lua`：加载实际兽王源，验证自动选源、SavedVariables 和
  M5/M4 像素协议动作；包括无绑定、空队列、移动、未知回退及怒火 → Thrash 成功事件。
- 全部 15 个 `Tests/*.test.lua` 在独立 Lua 5.1 / Lua 5.5 运行时执行；所有插件 Lua
  做语法检查，同时核对 TOC 依赖顺序和 `git diff --check`。
- 未启动/连接 WoW，未安装至游戏目录；离线矩阵不是实际客户端 secret 字段、光环发布
  时序及真实收益的实战证明。没有最新施法日志，也不能据此宣称已证明玩家此前浪费数量。

### 二次独立复核修复（2.13.18）

- 修复实际 LibStub 为可调用表时扫描库无法初始化；单元和核心集成均改用该真实形态。
- 原生 `1/2` 且恢复时序未知时，不再接受包装层矛盾的“满层”结果。
- 群体怒火的 Cleave 条件检查真实剩余，不把到期但仍列出的光环当作正面证据。
- 双目标且未点 Cleave 时，低位单体倒刺行本来不含 `target_if`，不再无故回退。
- 怒火未绑定且在倒刺前置近窗时，不擅自跳过倒刺前置去注入较低动作；保持原队列。
- Cobra Fang 接管增加实际四件套证据门，覆盖换装、错专精奖励、缺失/secret/异常数据。
- 新增固定种子的独立 APL 对照：32,000 个可读状态，以及 4,000 个隐藏布尔条件的
  真/假双向补全；自有输出必须在两种补全下均成立，未知回退必须返回原队列。
- 对 9 项关键逻辑执行内存变异验证：故意改坏初始化、充能满层、三个严格边界、
  Cleave 到期、M4 隔离、四件套门和 Howl 充能保留；全部被测试检出，不修改磁盘源码。

复现全部持久化 Lua 测试（仓库根目录，Python + Lupa 执行以下脚本）：

```python
from importlib import import_module
from pathlib import Path
for version in ('lua51', 'lua55'):
    Runtime = import_module('lupa.' + version).LuaRuntime
    for test in sorted(Path('JustACBridge.core/Tests').glob('*.test.lua')):
        print(version, test.name, flush=True)
        Runtime(unpack_returned_tuples=True).execute(test.read_text(encoding='utf-8-sig'))
```
