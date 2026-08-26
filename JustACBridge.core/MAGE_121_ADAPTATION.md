# 法师三系 12.1 适配依据（2026-08-26）

本轮只实现 Bridge 能从普通布尔值、明确法术归属、成功施法事件或 JustAC 的安全封装
可靠证明的规则。目标数量、光环层数、持续时间或投射物时序一旦不可读，就原样回退
当前 JustAC 队列，不用近似计时补全 APL。

## 当前推荐源

- NGA 奥法 PTR/S2：[S2 奥法循环变化 V1](https://bbs.nga.cn/read.php?tid=47085132)
- NGA 火法 PTR/S2：[S2 火法循环变化 V1](https://bbs.nga.cn/read.php?tid=47171968)
- NGA 团本实战：[英雄烈毒之渊/潮缚石窟法师心得](https://bbs.nga.cn/read.php?tid=47431968)
- SimulationCraft Midnight 当前法师 APL：
  [mage_arcane.simc](https://github.com/simulationcraft/simc/blob/midnight/ActionPriorityLists/default/mage_arcane.simc)、
  [mage.cpp](https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/apl/mage.cpp)
- Icy Veins 当前奥法循环：
  [Arcane Mage Rotation, Cooldowns, and Abilities](https://www.icy-veins.com/wow/arcane-mage-pve-dps-rotation-cooldowns-abilities)
- Wowhead 当前奥法循环：
  [Arcane Mage Rotation Guide](https://www.wowhead.com/guide/classes/mage/arcane/rotation-cooldowns-pve-dps)
- Method 当前冰法循环：
  [Frost Mage Playstyle and Rotation](https://www.method.gg/guides/frost-mage/playstyle-and-rotation)
- Icy Veins 当前冰法说明：
  [Frost Mage Guide](https://www.icy-veins.com/wow/frost-mage-pve-dps-guide)

NGA 法师区在调研日置顶的冰法链接已失效，因此没有猜测帖子编号；冰法以当前 SimC
APL、Method 与 Icy Veins 的交集为实现依据。

## 落地范围

### 奥术

- 保留现有 12.1 自有源与 M4/M5 特例，不把无法读取的动态优先级伪装成完整 APL。
- 所有自有动作先由 `IsPlayerSpell`/`IsSpellKnown` 正面确认归属。
- 对 API 返回值、光环持续时间和 JustAC 队列增加 `pcall` 与 secret/plain 校验。
- 自有源无法完整证明更高优先级条件时原样保留 JustAC 剩余动作的相对顺序；不再注入
  奥冲或把奥冲移动到 JustAC 推荐的弹幕之前。明确的合法性/安全过滤只能删除动作。
- 大法师之触按当前 SimC `use_off_gcd=1` 标记；只在自有源已证明触分支后让对应 M5
  槽绕过 GCD 门控，读条/引导保护和 M4 保留不变。
- 项目定制条件配对：涌动明确可用时先等待触也明确就绪，再先涌动、后触；触未就绪
  时从自有源和 JustAC 回退中跳过涌动。若涌动明确未学习、未绑定或不可用，合法的触
  分支可以直接释放；涌动在冷却时也直接放触，不再读取 DurationObject 阈值，不要求
  上一弹幕/Bolt。配对顺序只接受 10 秒内的 `UNIT_SPELLCAST_SUCCEEDED` 顺序证据。
- Icy Veins 与 Wowhead 的高级序列包含飞弹和弹幕，但项目按用户明确要求采用更可靠的
  `Arcane Surge → Touch of the Magi` 配对：涌动成功后只建立 `EXPECT_TOUCH`，下一动作
  直接优先触；失败、中断、意外 GCD、超时或无效目标立即取消。M4 不强制该序列。
- 上述状态凭据保存当前敌对 `targetGUID`。`PLAYER_TARGET_CHANGED`、
  GUID 不一致、目标死亡或不可攻击会同时清除上一 GCD、涌动配对与短状态机凭据；切回
  原 GUID 不会恢复旧凭据。
- 移动飞弹增加一次性实测兜底：浮光掠影和飞弹归属已确认、飞弹当前可用且确实位于
  推荐队列，但节能施法光环不可读时，每次连续移动允许试放一次。失败事件立即锁掉
  后续尝试直到真实停步；成功则进入既有的完整飞弹引导保护。
- 停步事件与试放碰撞时，当前试放实例被取消，下一安全技能至少导出一个完整刷新帧；
  再下一次计算若仍推荐飞弹，则它是新的静止动作实例，可以正常释放。速度为 secret
  时整个 STOP 防抖窗口禁止重新建立试放，避免旧试放在第二帧重新出现。
- 日怒补入四充能、齐射精确 25 层、涌动结束或剩余时间明确大于最大 GCD 时的独立
  弹幕分支，不把 25 层近似成普通 `>=12 + Clearcasting`。

### 火焰

- Firestarter 延迟燃烧期间禁用普通 Hot Streak 的 Flamestrike 切换；Pyroclasm 保留例外。
- Sunfury Execution 已学会且 Meteor 明确可用时，拥有燃烧前 Meteor 步骤。
- Frostfire Meteor 在 Burnout 构筑按燃烧剩余 `<8s`，无 Burnout 按 `>2s`；持续时间
  不可读时回退 JustAC。
- 12.1 M4 只在自光环明确缺失时维护 Blazing Barrier，并保留一层充能给手动机制。

### 冰霜

- 旧版本仍保留 Icy Veins；12.1 规则集改为保留 Ray of Frost，因为 Icy Veins 已在
  Midnight 移除。
- 12.1 禁用 JustAC Burst Trigger 自动合并，避免旧触发器把已移除技能重新加入。
- Frozen Orb、Blizzard、Cone of Cold 继续因无法可靠自动瞄准而从 M4 排除；Ray of
  Frost 继续全程保护引导。
