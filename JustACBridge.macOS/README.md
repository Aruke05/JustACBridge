# JustACBridge macOS

原生 macOS 实时映射器，与 `PIXEL_PROTOCOL.md` v1/v2/v3 兼容。默认将 **M5**
映射为无损版，将 **M4** 映射为保留爆发版，并复用 Windows 端的施法保护、
GCD 入队门控和 20ms 按住连发语义。

## 系统要求

- macOS 13 或更高版本
- 已安装并启用仓库中的 `JustACBridge.core`
- 屏幕录制、辅助功能和输入监听权限

## 构建

```bash
cd JustACBridge.macOS
./build_macos.sh
```

输出：

```text
JustACBridge.macOS/dist/JustACBridge.app
```

## 使用

1. 在 WoW 中输入 `/jacb pixels on`。
2. 启动 `JustACBridge.app`，按系统提示授予屏幕录制和辅助功能权限。
3. 首次授权后退出并重新打开应用。
4. 看到绿色“实时映射已启用”后，按住 M5 或 M4。
5. 如需换键，点击对应的“设置功能键”，再按一次目标鼠标键或键盘键。

macOS 会按应用签名和路径记录隐私授权。重新构建或移动应用后，系统可能要求重新
授权。像素读取依赖 WoW 窗口可见；完全最小化时不会产生有效帧。

应用默认使用每 5ms 捕获一次的均衡模式，也可以切换到“极限”连续捕获模式。
映射配置通过 `UserDefaults` 保存在当前用户偏好中。
