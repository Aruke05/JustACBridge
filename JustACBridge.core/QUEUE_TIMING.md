# 稳定优先的入队时机修正（插件 2.13.1 / Windows 2.12.35）

## 范围

- 这是输入调度修正，不是 APL、技能过滤或优先级变更。
- 每次核心刷新读取 `C_CVar.GetCVar("SpellQueueWindow")`；仅接口缺失时兼容全局
  `GetCVar`。已知有效值使用 `min(120, floor(gameWindowMs))`，0 保持为 0。
- API 缺失、抛错、nil、非法数字或 secret 时，标明未知并保留旧 120ms 行为，
  不沿用上一帧设置，不声称这个兼容回退值适合当前实际网络。
- 不扩大原 120ms 上限，不修改游戏 CVar，不用 ping 猜测单程延迟。
- 技能就绪判断的原 120ms look-ahead 与实际按键发送窗口分别处理，不能借调度重写队列。
- Windows 同键 250ms 间隔、飞弹开始锁、完整读条/引导保护、M4/M5 独立权限均保持原样。
- 像素协议仍为 v3/v4；macOS 继续读取 `queueReady`，没有修改或重新构建 macOS 客户端。

## 已复现的边界及限制

在假设游戏窗口为 80ms、零传输延迟、20ms 轮询且第一次输入未被游戏接收的模型中，
旧调度在 GCD 前 120ms 首发，同键限流导致下次检查到 GCD 后 140ms 才重发。
新调度将首次尝试移到游戏允许的窗口内；不靠放开重复发送解决问题。

此模型不是游戏实测。真实网络、帧时序、服务器接收、GCD API/secret 行为以及实际 DPS
不能由离线测试证明。当前 GCD API 读取逻辑未改动；不能将 CVar 的 secret 防护宣传成
整个核心已解决所有 secret 问题。读条/引导结束后的保守空档仍然存在。

## 诊断

- 游戏 `SNAP`：`commitMs`（采用的上限）、`gameQueueMs`（公开读值或 nil）、
  `queueTiming`（读取结果），以及原有 `gcdMs/queueReady/cast/channel`。
- SavedVariables：`queueCommitWindowMs/gameSpellQueueWindowMs/queueTimingReason`。
  窗口变化本身触发导出更新，不要求技能 ID 或门控布尔值同时变化。
- Windows：每次实际输入尝试记录 `SEND`；不再每 500ms 抽样。等待同键限流时只记录
  状态切换。日志的本地 `tick` 与游戏时间不是同一个时钟，不能直接相减。
- 结合原始 `QUEUE/SOURCE_DECISION/SELECT` 与成功施法事件诊断，不用伤害占比推断时序。

## 离线验证

- `lua JustACBridge.core/Tests/QueueTiming.test.lua`：0、边界、实时变化、API 缺失/异常、
  nil、NaN、无穷大、secret、legacy getter 与未知值不缓存。
- `lua JustACBridge.core/Tests/CoreIntegration.test.lua`：完整核心刷新、双路推荐不变、
  窗口改变时的导出、实际像素编码的 gate/busy 位与三项校验、读条和引导保护。
- 对 `JustACBridge.core/Tests/*.test.lua` 全量执行，每个文件使用独立 Lua 环境。
- `dotnet run --project JustACBridge.M5 -c Release -- --self-test`：生产客户端内置自测。
- `dotnet run --project JustACBridge.M5.Tests -c Release`：实际 M5Hook 配合无副作用输入与
  日志替身，验证提前入队模型、限流、每次发送日志、去重日志、松键与保护状态。
- 不调用 `--probe`、`--hook-test` 或普通 GUI 启动入口。

2026-09-06 本次执行结果：Lua 5.1 与 LuaJIT 2.1 各通过 38 个 Lua 文件语法检查、
10 个测试套件；Windows Release 内置自测、独立离线 hook 测试与 self-contained
单文件发布产物的 `--self-test` 全部通过。未执行游戏实战或 macOS 原生客户端测试。

## 依据

- [用户提供的视频](https://www.bilibili.com/video/BV1fewmzHEdc/)：提前入队减少空档的动机；
  不采用其固定 DPS 损失或“一种窗口永远最佳”的泛化结论。
- [暴雪生成的 CVar API 文档源码镜像](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CVarDocumentation.lua)：
  `C_CVar.GetCVar` 返回值为可空字符串。2026-09-06 查阅；代码保留未知/异常路径。
