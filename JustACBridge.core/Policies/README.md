# 职业策略扩展

`Registry.lua` 是唯一公共入口；职业文件只登记数据，不参与像素协议、按键解析或
JustAC 队列读取。

## 新增职业

1. 新建 `Policies/<ClassFile>.lua`。
2. 调用 `JustACBridgePolicyRegistry.RegisterClass("CLASSFILE", definition)`。
3. 在 `JustACBridge.toc` 的 `JustACBridge.lua` 之前增加该文件。

没有登记策略的职业仍可工作：Bridge 会使用 JustAC 当前专精检测到的
`Burst Trigger`，只是没有 Bridge 内置兼容表。

## 游戏版本变动

稳定的默认规则放在专精的 `reserve` 中。版本差异放在 `versions`，无需修改主循环：

```lua
[2] = {
    id = "example",
    name = "示例",
    revision = 2,
    reserve = { 1001, 1002 },
    versions = {
        {
            id = "12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 3,
            addReserve = { 1003 },
            removeReserve = { 1001 },
        },
        {
            id = "13.0",
            minInterface = 130000,
            revision = 4,
            reserve = { 2001, 2002 }, -- 完整替换
        },
    },
}
```

选择规则：

- Interface 区间匹配时，`minInterface` 最大的补丁生效。
- `reserve` 表示完整替换；`removeReserve` 后执行 `addReserve`。
- 玩家 `/jacb reserve add/remove` 最后执行，始终高于内置策略。
- SavedVariables 继续使用稳定键 `CLASSFILE_<专精序号>`，拆文件或升版本不会丢失
  现有覆盖。
