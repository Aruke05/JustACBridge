# JustACBridge 实时像素协议 v1（规范）

> **给 Codex/实现者的结论：** 这是一个把 JustAC 前两个推荐技能及快捷键从
> WoW 插件传给 Windows 外部程序的只读、低延迟屏幕协议。不要用
> SavedVariables 做实时读取。外部程序应捕获 WoW **客户区左上角附近**的
> 黑白位矩阵，自动拟合像素单元间距，恢复 72 字节，最后验证协议头、尾部和
> 三项校验。仓库中的规范实现是
> `reader_test/justacbridge_reader.py`。

本文是自包含规范；只阅读本文即可重新实现兼容读取器。

## 1. 数据流和延迟

```text
JustAC-SpellQueue.GetCurrentSpellQueue()
        ↓
JustACBridge 取队列前两项
        ↓
JustAC-ActionBarScanner.GetSpellHotkey()
        ↓
生成 72 字节协议包
        ↓
按位渲染为 48 列 × 12 行黑白矩阵
        ↓
外部程序捕获 WoW 客户区并解码
```

- 插件每个渲染帧检查一次队列。
- JustAC 自身对队列计算有约 30/50 ms 的内部节流。
- 外部参考读取器默认每 5 ms 捕获一次。
- 当前机器实测持续解码平均约 4.15 ms，P95 约 5.55 ms。
- `SavedVariables` 仅在退出或 `/reload` 时落盘，只是持久化备份，不是实时链路。

## 2. 屏幕传输层

### 2.1 矩阵

- 位数：`576 bit = 72 byte`
- 布局：`48` 列 × `12` 行
- 顺序：从左到右、从上到下（row-major）
- 字节位序：最高有效位优先（MSB first）
- 黑色单元：位 `0`
- 白色单元：位 `1`
- 判定阈值：单元中值亮度 `>= 128` 为 `1`，否则为 `0`

位索引与矩阵坐标：

```text
column = bitIndex % 48
row    = floor(bitIndex / 48)
```

位索引与字节：

```text
byteIndex = floor(bitIndex / 8)
bitInByte = 7 - (bitIndex % 8)
payload[byteIndex] |= bitValue << bitInByte
```

### 2.2 位置和缩放——必须自动拟合

插件把矩阵锚定在 WoW 客户区左上角附近，名义偏移为 `(2, 2)`，名义单元大小
为 `3 × 3` UI 单位。但是 WoW UI Scale、Windows DPI 和窗口合成会改变最终
物理像素大小。

**不要假设屏幕上一定正好是 144 × 36 物理像素。**

参考读取器采用以下策略：

1. 将进程设为 Per-Monitor DPI Aware。
2. 使用 `ClientToScreen()` 得到 WoW 客户区左上角。
3. 从客户区坐标 `(2, 2)` 开始，捕获至少 `296 × 80` 物理像素。
4. 搜索单元间距 `pitch = 2.00 .. 6.00`，步长 `0.01`。
5. 搜索捕获区域内起点偏移 `originX/originY = 0 .. 4`。
6. 用已知开头 `JAC` 的 24 个比特快速筛选候选几何参数。
7. 对候选参数恢复全部 72 字节，并用三项校验确认。
8. 找到后缓存 `(pitch, originX, originY)`；校验失败时丢弃缓存并重新拟合。

当前实测拟合结果示例：

```text
pitch=3.41 origin=(1,0)
```

这正是读取器不能硬编码 `3 px` 单元的原因。

### 2.3 单元采样

已知 `pitch` 与起点后，第 `column,row` 个单元的中心采样点为：

```text
x = originX + floor((column + 0.5) * pitch)
y = originY + floor((row    + 0.5) * pitch)
```

参考读取器采中心像素。若捕获环境有缩放噪声，也可以采单元中心附近多个像素，
用亮度中值判定黑白。

## 3. 72 字节包格式

下表偏移均为 **零基（zero-based）**。所有多字节整数均为无符号小端序。

| 偏移 | 大小 | 字段 | 说明 |
|---:|---:|---|---|
| 0 | 3 | `magic` | ASCII `JAC`，十六进制 `4A 41 43` |
| 3 | 1 | `version` | 当前固定为 `1` |
| 4 | 2 | `sequence` | 变化序号，uint16 little-endian，会回绕 |
| 6 | 1 | `flags` | 推荐存在、类型、按键状态，见下一节 |
| 7 | 3 | `firstID` | 第一推荐的法术或物品 ID，uint24 little-endian |
| 10 | 1 | `firstKeyLength` | 第一快捷键字节数，范围 `0..24` |
| 11 | 24 | `firstKey` | 第一快捷键 UTF-8/ASCII，尾部补零 |
| 35 | 3 | `secondID` | 第二推荐的法术或物品 ID，uint24 little-endian |
| 38 | 1 | `secondKeyLength` | 第二快捷键字节数，范围 `0..24` |
| 39 | 24 | `secondKey` | 第二快捷键 UTF-8/ASCII，尾部补零 |
| 63 | 3 | `gameTickMs` | `floor(GetTime()*1000) mod 2^24`，uint24 LE |
| 66 | 1 | `sum1` | 对字节 `0..65` 的 Fletcher sum1 |
| 67 | 1 | `sum2` | 对字节 `0..65` 的 Fletcher sum2 |
| 68 | 1 | `rolling` | 对字节 `0..65` 的滚动校验 |
| 69 | 3 | `trailer` | ASCII `END`，十六进制 `45 4E 44` |

### 3.1 flags

| 位掩码 | 含义 |
|---:|---|
| `0x01` | 第一推荐存在 |
| `0x02` | 第一推荐是物品；未设置时是法术 |
| `0x04` | 第一推荐已找到快捷键 |
| `0x08` | 第二推荐存在 |
| `0x10` | 第二推荐是物品；未设置时是法术 |
| `0x20` | 第二推荐已找到快捷键 |
| `0x40` | 玩家正在持续引导（channeling） |
| `0x80` | 玩家正在普通读条或蓄力施法（casting/empowering） |

`0x40` 与 `0x80` 正常情况下互斥：

- 两者都是 `0`：空闲或瞬发技能；
- `0x40`：正在持续输出/引导技能；
- `0x80`：正在释放普通读条技能，或正在进行 Evoker 类蓄力施法。

插件通过玩家自己的 `UNIT_SPELLCAST_CHANNEL_START/STOP`、
`UNIT_SPELLCAST_START/STOP` 和 `UNIT_SPELLCAST_EMPOWER_START/STOP` 事件维护状态，
不会把瞬发技能误判为读条。

JustAC 用负数表示队列中的物品，例如 `-5512`。协议中发送正 ID `5512`，并设置
对应的 item flag。

推荐不存在时，相应 exists flag 清零，ID 和长度为零。读取器应以 exists flag
为准，而不是只判断 ID。

### 3.2 快捷键

- 传输的是 JustACBridge 的 `plainHotkey`，不是 WoW 的纹理转义字符串。
- 键盘示例：`1`、`SHIFT-1`、`CTRL-F`。
- 手柄纹理会转换为 `PAD1`、`PAD2` 等纯文本。
- 最多传输 24 字节；长度字段表示实际有效字节数。
- 名称不在像素协议中。外部程序得到的是 ID、类型和快捷键；需要名称时自行按
  ID 查询，或在非实时场景读取 SavedVariables。

### 3.3 sequence 与 gameTickMs

- `sequence` 只占 16 位，比较时必须允许 `65535 → 0` 回绕。
- 读取器通常只在 sequence 变化时向上游输出新结果。
- `gameTickMs` 占 24 位，约每 4 小时 39 分 37.216 秒回绕。
- 不要把 `gameTickMs` 当 Unix 时间；它主要用于识别陈旧截图和调试。

## 4. 校验算法

只对 `payload[0:66]`，即偏移 `0..65` 计算：

```python
sum1 = 0
sum2 = 0
rolling = 0

for value in payload[0:66]:
    sum1 = (sum1 + value) % 255
    sum2 = (sum2 + sum1) % 255
    rolling = (rolling * 33 + value) % 256
```

有效包必须同时满足：

```text
payload[0:3]   == b"JAC"
payload[3]     == 1
payload[66]    == sum1
payload[67]    == sum2
payload[68]    == rolling
payload[69:72] == b"END"
```

任意一项失败都必须丢弃整帧。这也能拒绝刚好在插件重绘矩阵过程中截到的撕裂帧。

## 5. 推荐的完整读取流程

```text
定位唯一的 WoW 窗口
  → 获取客户区屏幕坐标
  → 捕获左上角 296×80 区域
  → 若无缓存几何参数：用 JAC + 校验拟合 pitch/origin
  → 恢复 576 bit / 72 byte
  → 校验 JAC、version、三项 checksum、END
  → 解析 flags、两个 ID、两个 hotkey
  → sequence 未变化：不重复输出
  → sequence 变化：输出新推荐
  → 校验失败：丢帧并重新拟合几何参数
```

不要通过窗口标题的模糊包含匹配直接选择窗口，因为浏览器标签标题可能包含
“World of Warcraft”。优先匹配 `Wow.exe`，或者精确匹配窗口标题“魔兽世界”/
“World of Warcraft”。

GDI `BitBlt` 读取桌面表面时，WoW 窗口需要可见且不被其他窗口遮挡。使用
Windows Graphics Capture 或 Desktop Duplication API 的实现可以避免部分遮挡问题，
但解码协议完全相同。

## 6. 实际有效包示例

本机从正在运行的 WoW 实际读取到：

```text
raw_hex =
4a41430101002dea4a0101340000000000000000000000000000000000000000000000f7760001310000000000000000000000000000000000000000000000c028c8bbcf16454e44
```

解析结果：

```json
{
  "version": 1,
  "sequence": 1,
  "game_tick_ms": 13117632,
  "is_channeling": false,
  "is_casting": false,
  "first": {
    "exists": true,
    "kind": "spell",
    "id": 84714,
    "hotkey": "4",
    "bound": true
  },
  "second": {
    "exists": true,
    "kind": "spell",
    "id": 30455,
    "hotkey": "1",
    "bound": true
  }
}
```

## 7. 仓库内参考实现与测试

规范读取器：

```text
reader_test/justacbridge_reader.py
```

离线测试：

```powershell
cd reader_test
python -m unittest -v
```

实时读取一次：

```powershell
python justacbridge_reader.py --once --timeout-seconds 10 --debug-errors
```

持续 JSON Lines：

```powershell
python justacbridge_reader.py --json
```

游戏内控制：

```text
/jacb pixels on
/jacb pixels off
```

矩阵默认开启，并且独立于普通两行 UI；隐藏普通面板不会关闭像素接口。

## 8. 兼容性要求摘要

兼容 v1 的读取器必须：

1. 按 48×12、row-major、MSB-first 恢复 72 字节。
2. 自动适配实际物理 pitch，不硬编码 3 像素。
3. 验证 `JAC`、版本、三项校验和 `END`。
4. 按 flags 区分法术、物品、未绑定与不存在。
5. 允许 sequence 和 gameTickMs 回绕。
6. 校验失败时丢弃整帧，不能输出部分结果。
7. 将 SavedVariables 视为持久化备份，而非实时接口。
