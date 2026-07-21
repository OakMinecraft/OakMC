# OakMC 插件开发快速上手

[Lua API 参考](lua-api-reference-zh.md)

这一页带你开发第一个 OakMC Lua 插件。完整 API 类型、函数参数和返回值见
[Lua API 参考](lua-api-reference-zh.md)。

OakMC 内嵌 Lua 5.4，用于玩法插件和服务端实验。服务端从 `plugins/*.lua`
收集插件，校验依赖图后按拓扑顺序初始化。`reload-lua` 会按依赖顺序的反向
调用关闭钩子、注销 Lua 事件、重建虚拟机并重新加载插件，不会踢出在线玩家
或重载 `server.properties`。

## 1. 开发前准备

为了更便利的插件开发体验，建议你将 `scripts/oakmc_api.lua` 放在插件工作目录
或把编辑器的 Lua 补全路径指向这个文件。它会向代码编辑器提供 OakMC Lua API
的补全和类型提示。

插件文件放在：

```text
plugins/*.lua
```

## 2. 第一个插件

创建插件文件保存为 `plugins/hello.lua`。

你需要向 OakMC 声明插件必要的信息。下面是插件必须或可选的信息清单：

| 字段 | 是否必需 | 类型 | 说明 |
| --- | --- | --- | --- |
| `init` | 必需 | `function` | 插件初始化函数。OakMC 校验所有插件和依赖成功后调用，事件注册、命令注册、实体生成等有副作用的逻辑应放在这里。 |
| `name` | 可选 | `string` | 插件名称。用于依赖声明和重复名称检查；建议每个插件都显式填写一个稳定、唯一的名称。 |
| `depends` | 可选 | `table` | 依赖插件名称数组，例如 `{"core", "economy"}`。OakMC 会先初始化依赖插件，再初始化当前插件。 |
| `shutdown` | 可选 | `function` | 插件卸载函数。执行 `reload-lua`、`reload`、切换世界或关闭服务端时调用，适合清理插件创建的运行时状态。 |

如下是一个实例插件完整结构：

```lua
local function init()
    mcs_server_send_message("hello from Lua plugin", MCS_LOG_INFO)
end

local function shutdown()
    mcs_server_send_message("Lua plugin stopped", MCS_LOG_INFO)
end

return {
    name = "hello",
    depends = {},
    init = init,
    shutdown = shutdown,
}
```

`mcs_server_send_message(message, log_type)` 会向服务端日志输出消息。这里使用
`MCS_LOG_INFO`，也可以使用 `MCS_LOG_WARN` 或 `MCS_LOG_ERROR`。

## 3. 监听玩家加入事件

事件监听建议在 `init()` 中注册。下面的插件会在玩家加入后发送标题和音效：

```lua
local function on_join(event)
    local player = event.playername
    if player == nil then
        return
    end

    mcs_title_set_time(player, 10, 70, 20)
    mcs_title_set_subtitle_text(player, "By OakMC")
    mcs_title_set_text(player, "Welcome")
    mcs_player_play_sound_name(player, "minecraft:entity.player.levelup", 0, 1.0, 1.0, 0)
end

local function init()
    mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, on_join)
end

return {
    name = "welcome",
    init = init,
}
```

`mcs_event_register(event_type, priority, callback, options)` 用于注册事件处理函数。
`priority` 越大越先执行；可取消事件中设置 `event.cancelled = true` 可以阻止
后续默认行为或后续 handler。

## 4. 注册一个命令

Lua 插件也可以注册服务端命令。下面的命令可以由控制台或玩家执行：

```lua
local function hello(context, args)
    local message = #args > 0 and table.concat(args, " ") or "Hello from Lua"

    if context.playername ~= nil then
        mcs_title_set_action_bar_text(context.playername, message)
    else
        mcs_server_send_message(message, MCS_LOG_INFO)
    end

    return true
end

local function init()
    mcs_command_register(
        "luahello",
        "luahello [message]",
        "显示由 Lua 提供的问候",
        false,
        hello
    )
end

return {
    name = "command-demo",
    init = init,
}
```

命令回调返回 `false` 表示参数无效，服务端会显示注册时提供的 usage；返回
`true` 或 `nil` 表示执行成功。

## 5. 插件生命周期和依赖

插件加载被明确分成几个独立阶段：

1. 执行所有 `plugins/*.lua` 文件，收集每个文件返回的模块表，此时不调用
   `init()`。
2. 在完整插件集合中，根据名字查找每个 `depends` 条目对应的插件。
3. 校验整张依赖图，生成依赖在前、使用者在后的初始化列表。
4. 只有全部插件和依赖都校验成功后，才按照列表调用 `init()`。

缺失依赖、重复插件名、自依赖和循环依赖会在初始化前被拒绝。如果依赖图中的
任何位置存在错误，即使已经计算出一部分顺序，也不会调用任何插件的 `init()`。

为了取得模块表，所有插件文件的顶层代码都会在收集阶段执行，而此时依赖尚未
校验。因此插件顶层应只定义函数和模块数据；事件注册及其他有副作用的操作应放
进 `init()`。

一个插件可以声明多个依赖：

```lua
return {
    name = "economy",
    depends = {"core1", "core2"},
    init = init,
    shutdown = shutdown,
}
```

依赖解析只记录初始化顺序，不会一边查找一边调用 `init()`。一个插件只有在它的
全部依赖都解析完成后才会被加入列表；被多个插件共同依赖的插件只会记录并初始化
一次。

`reload` 同样会在保留玩家连接的情况下重载 Lua；当 `level-name` 改变或执行
`world load <name>` 时，服务端会先按反向依赖顺序调用旧世界插件的
`shutdown()`，注销 Lua 事件并清除普通运行时实体，完成存档切换后再按依赖
顺序执行新世界插件的 `init()`。插件不应假定 Lua 全局变量可以跨世界切换
保留；需要持久化的数据应由插件自行写入磁盘。

## 6. 调试建议

- 使用 `mcs_server_send_message(..., MCS_LOG_INFO)` 输出关键状态。
- 查询类 API 可能返回 `nil`，使用玩家、实体、物品或世界数据前先判断。
- 修改客户端显示和修改服务端状态是两类不同操作，例如可视装备不会改真实背包。
- 需要补全和类型提示时，把编辑器指向 `scripts/oakmc_api.lua`。
- 更完整的成品脚本见 `scripts/example/`。
