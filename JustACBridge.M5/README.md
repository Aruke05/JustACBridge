# JustACBridge M5

原生 Windows 实时映射器：连续读取 `PIXEL_PROTOCOL.md` 的第一推荐快捷键，并把鼠标前侧键 **M5 / XBUTTON2** 动态替换为该快捷键。

当协议报告玩家正在持续引导（`0x40`）、普通读条或蓄力施法（`0x80`）时，程序会**完全吞掉 M5 的按下和松开事件，不发送快捷键，也不把原始 M5 传给游戏**。若 M5 已经按住，进入读条状态时也会立即释放之前注入的键，并继续吞掉这次 M5 的松开事件。只有读到校验正确且明确为空闲状态的数据包后才恢复映射。

## 使用

1. 在 WoW 内输入 `/jacb pixels on`。
2. 保证 WoW 窗口可见、左上角像素矩阵未被其他窗口遮挡。
3. 双击 `JustACBridge.M5.exe`；看到绿色“实时映射已启用”后即可按 M5。
4. 如果 WoW 以管理员身份运行，本程序也应以管理员身份运行，否则 Windows 会阻止输入注入。

按下 M5 时会锁定当时的第一推荐快捷键，松开时释放同一组键，避免推荐在按住期间变化造成卡键。无有效推荐、未绑定或不支持的键不会拦截 M5。

## 延迟路径

- “极限”模式无主动 `Sleep`，专用最高优先级线程连续执行小区域 GDI 捕获。
- 只在几何参数丢失时搜索 `pitch=2.00..6.00`；稳定后直接解码 576 bit。
- 低级鼠标钩子在独立最高优先级消息线程中运行；M5 到 `SendInput` 不经过 UI。
- 三项校验全部通过后才原子更新当前快捷键。

零延迟在现实系统中不可能；本程序不额外排队，通常额外延迟受一次屏幕捕获/桌面合成刷新限制。GDI 路径要求游戏可见且不被遮挡。

## 构建

```powershell
dotnet publish .\JustACBridge.M5.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

输出位于 `bin\Release\net10.0-windows\win-x64\publish\JustACBridge.M5.exe`。
