# Hunter 12.1 适配说明

## 结论

12.1 的兽王、射击和生存猎均注册独立策略与自动推荐源。M5 只覆盖当前运行时能够完整
证明的 APL 切片；所有依赖 secret、目标评分、剩余战斗时间、下一波时间、充能小数或
引导剩余 tick 的分支都原样回退 JustAC。M4 始终读取原始 JustAC 队列，只做本专精的
爆发保留、移动、引导、方向/地面与通用合法性过滤。

这不是把部分规则包装成完整 APL。`SOURCE_DECISION` 中出现 `fallback=true` 表示该帧
仍由 JustAC 保持原始优先级。

## 参考基线（2026-09-02 核验）

- SimulationCraft `midnight` 分支 Hunter APL：
  <https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/apl/apl_hunter.cpp>
  - 本地研究副本 SHA-256：
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
| `full_recharge_time<gcd`、充能小数 | 无精确 plain 数值 | 除“已满充能”外回退 |
| 冷却剩余 `<gcd`/`>gcd` | 只有冷却开关时不充分 | 就绪可证明剩余为 0；其余回退 |
| `target_if`、优先目标、DungeonRoute 下一波 | 无可靠目标评分/路线时钟 | 原样回退 JustAC |
| `fight_remains`、`time_to_die` | 无可靠战斗时长 | 原样回退 JustAC |
| Rapid Fire `ticks_remain<2` | 无可靠剩余 tick | 不实现截断，完整保护引导 |
| 人物到目标方向/自动转向 | 副本内不可可靠取得并控制 | M4 排除前方锥形技能 |

## 三系行为

### 兽王 `bmhunter121`

- 自动识别 Pack Leader；Dark Ranger 的 Withering Fire 时长、Wailing Arrow 收尾和
  target 条件无法完整证明时交回 JustAC。
- 正面实现：Bestial Wrath 就绪前的 Barbed Shot、Barbed Shot 满充能、防止 BW 后
  Apex 宠物漏掉 Beast Cleave 的 Wild Thrash，以及可见 Cobra Fang 层数消费。
- M4 精确保留 Bestial Wrath；Black Arrow、Wild Thrash、Barbed Shot、Kill Command
  保持普通循环身份。
- Wailing Arrow 强制按真实读条处理，不因按钮高亮被误判为移动瞬发。

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
