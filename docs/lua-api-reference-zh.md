# OakMC Lua API 参考

[English](lua-api-reference.md)

OakMC 内嵌 Lua 5.4，用于玩法插件。本文介绍 Lua 插件 API 的使用约定、
分类、函数参数、返回值、常量和示例。第一次编写插件时，请先阅读
[插件开发快速上手](plugin-development-zh.md)。

## 1. API 使用约定

### 1.1 客户端可见 API 的受众语义

客户端可见动作的参数表示“谁接收这次显示数据包”，不一定表示“谁被修改”。
受众统一分为三类：无后缀的新接口如果带 `viewer_name` 或 `playername`，只把数据包发给
这个玩家的客户端；`*_for_others(owner_entity_id, ...)` 发送给除实体所有者之外的已初始化客户端；
`*_for_all(...)` 发送给所有已初始化客户端（包括所有者）。例如装备显示接口中，
`viewer_name` 是看见装备变化的玩家，`entity_id` 才是被显示装备的实体。
玩家生命值、背包、游戏模式、效果、飞行权限、传送等服务端状态接口仍然按
`playername` 修改目标玩家，不属于广播接口。旧接口保留用于兼容，新增后缀接口
用于避免“函数名看似广播、实际只发一个人”或“无意把包发回所有者”的歧义。
少数旧函数（例如 `mcs_player_swing_hand(playername, hand)` 和 Lua 中作为日志
别名的 `mcs_chat_send_system_message`）保留原行为；新代码应使用显式受众版本。

目前已统一的客户端可见接口族包括：系统聊天、装备显示、受击动画、拉弓动画、挥手动画、
标题/副标题/Action Bar、粒子、侧边栏计分板、BossBar 和声音。比如
`mcs_title_set_text_for_all(text)`、`mcs_chat_send_system_message_for_all(message)`、
`mcs_particle_spawn_for_others(owner_entity_id, ...)`、
`mcs_scoreboard_sidebar_set_score_for_all(...)`、
`mcs_player_boss_bar_update_health_for_others(owner_entity_id, ...)` 和
`mcs_player_play_sound_for_all(...)` 都遵循同一规则。

### 1.2 返回值

大多数 Lua 辅助函数成功时返回 `true`，失败时返回 `false`。查询类函数成功时
返回 table；目标不存在或当前 API 无法表示目标时返回 `nil`。

重要例外：

- `mcs_block_get_state(x, y, z)` 返回 block state id。
- `mcs_block_state_id_from_name(block_name)` 返回默认 block state id，名称未知时
  返回 `nil`。
- `mcs_block_is_solid(x, y, z)` 和
  `mcs_block_state_is_solid(block_name_or_state_id)` 返回 boolean。
- `mcs_entity_spawn(...)` 返回新分配的运行时 `entity_id`，失败时返回 `nil`。
- `mcs_player_count()` 返回在线玩家数量。
- `mcs_player_get_gamemode(playername)` 返回 gamemode id，失败时返回 `nil`。

### 1.3 Text Component 与物品名称输入

带文本的 API 使用两条相关但不同的输入路径：

- title/subtitle/Action Bar、BossBar 标题、GUI 标题、实体自定义名称和实体
  生成时的可选名称支持普通文本或 JSON Text Component
- 带物品的 API 接受可选 `nbt_data`，但当前实现只把它映射为 ItemStack 的
  `minecraft:custom_name` 组件
- 物品自定义名称可以是普通文本、`{CustomName:'文本'}`，或者直接传 JSON
  Text Component，例如
  `{"text":"命名物品","color":"aqua","italic":false}`
- 传 `nil` 或空字符串不会添加任何物品组件
- 当前不是任意原始 NBT 支持；格式错误或不支持的 JSON/NBT-like 输入会在
  发包前被拒绝

## 2. API 分类参考

下面按服务端、方块、实体、世界、玩家、背包、界面、声音、粒子和事件分类介绍
Lua API。API 条目按“名称、运行端、描述、参数、返回值、示例”的结构书写，
方便日常开发时逐条查询。

### 2.1 服务端与聊天

#### mcs_server_send_message

服务端

描述

向服务端日志输出一条消息。`log_type` 用于指定日志级别，省略时由运行时使用默认日志级别。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `message` | `string` | 要输出的日志文本。 |
| `log_type` | `integer` | 可选。日志级别：`MCS_LOG_DEBUG` 调试信息，`MCS_LOG_INFO` 普通信息，`MCS_LOG_WARN` 警告，`MCS_LOG_ERROR` 错误。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 输出成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_server_send_message("hello from Lua plugin", MCS_LOG_INFO)
```

#### mcs_server_shutdown

服务端

描述

请求优雅关闭当前服务器。请求会在当前 Lua 回调结束后处理：插件初始化期间由启动流程处理，正常运行期间由服务端 tick 线程处理。关闭流程会保存脏区块、按逆序调用插件 `shutdown()`，并停止远程指令桥。请求提交后不应再安排依赖后续 tick 的工作。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 关闭请求被接受或已经处于待关闭状态时返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_server_shutdown()
```

#### mcs_server_get_port

服务端

描述

获取当前进程最终生效的 Minecraft 监听端口，包括命令行覆盖后的端口。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 当前服务端监听端口。 |

示例

```lua
local port = mcs_server_get_port()
mcs_server_send_message("current port: " .. port, MCS_LOG_INFO)
```

#### mcs_server_port_is_available

服务端

描述

对指定端口执行一次真实 TCP bind 探测。它不会连接 Minecraft 服务端，也不会查询在线人数。返回 `true` 表示当前可以绑定该端口；返回 `false` 通常表示已经有本地监听者占用，但 socket 或 bind 本身出错时也会返回 `false`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `port` | `integer` | 要探测的本地 TCP 端口，范围为 `1..65535`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 端口当前可绑定返回 `true`，不可绑定或探测失败返回 `false`。 |

示例

```lua
if mcs_server_port_is_available(25566) then
    mcs_server_send_message("port 25566 is available", MCS_LOG_INFO)
end
```

#### mcs_server_find_available_port

服务端

描述

从指定端口开始逐个执行真实 TCP bind 探测，直到 `65535`。端口探测和子进程启动之间仍存在极短的竞争窗口，因此调用方仍需处理 `mcs_server_start_instance` 失败。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `start_port` | `integer` | 可选。开始探测的端口；省略时默认从 `10000` 开始。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 找到空闲端口时返回第一个可绑定端口。 |
| `nil` | 没有可用端口或探测失败。 |

示例

```lua
local port = mcs_server_find_available_port(10000)
if port ~= nil then
    mcs_server_send_message("available port: " .. port, MCS_LOG_INFO)
end
```

#### mcs_server_start_instance

服务端

描述

在 `instances/<instance_name>/` 隔离工作目录中启动当前 OakMC 可执行文件，并等待目标回环端口真正开始接受连接。实例名仅允许字母、数字、连字符和下划线。启动过程不会携带经济、公告、玩家或其他业务数据；跨服状态与指令同步统一使用 `mcs_remote_command_send` 和签名通信桥。

提供 `remote_port` 时，C 层会请求启动子服 Remote，子服的 `server-id` 自动使用 `instance_name`。C 层把父进程最终生效的 secret 写入实例目录内权限受限的保留文件，再把文件路径传给子进程；Lua 不会获得密钥内容。如果父进程没有有效 Remote secret，同一个子服仍会正常启动，但 Remote 保持关闭。`allowed_commands` 可选，默认空白名单，即拒绝所有入站指令。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `instance_name` | `string` | 子服实例名，也是 `instances/` 下的隔离目录名。 |
| `port` | `integer` | 子服 Minecraft 监听端口。 |
| `remote_port` | `integer` | 可选。子服 Remote 监听端口。 |
| `allowed_commands` | `string` | 可选。允许远程执行的命令白名单，使用不带空格的逗号分隔命令名，例如 `stop,say`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 子服启动并开始接受连接后返回 `true`，失败返回 `false`。 |

示例

```lua
local port = assert(mcs_server_find_available_port(10000))
assert(mcs_server_start_instance("arena_1", port))
```

#### mcs_server_start_instance_from

服务端

描述

从模板目录创建动态房间。它会把现有的 `instances/<template_name>/` 复制为新的隔离目录 `instances/<instance_name>/`，然后从新目录启动子服。复制时跳过 `log/`、`crashes/`、`remote.properties` 和保留的实例密钥文件，防止房间继承旧日志、凭据或争用模板的 Remote 监听端口；世界、插件和 `server.properties` 会独立复制。可选 Remote 参数的行为与 `mcs_server_start_instance` 相同。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `template_name` | `string` | 模板实例目录名，对应 `instances/<template_name>/`。 |
| `instance_name` | `string` | 新子服实例名，对应 `instances/<instance_name>/`。 |
| `port` | `integer` | 新子服 Minecraft 监听端口。 |
| `remote_port` | `integer` | 可选。新子服 Remote 监听端口。 |
| `allowed_commands` | `string` | 可选。允许远程执行的命令白名单，例如 `stop,say`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 动态房间复制、启动并开始接受连接后返回 `true`，失败返回 `false`。 |

示例

```lua
local game_port = assert(mcs_server_find_available_port(10000))
local remote_port = assert(mcs_server_find_available_port(20000))
assert(mcs_server_start_instance_from(
    "arena_template",
    "arena_1",
    game_port,
    remote_port,
    "stop,say"
))
```

#### mcs_server_delete_current_instance

服务端

描述

删除当前动态房间。该 API 仅能在 `mcs_server_start_instance_from()` 创建并标记的动态房间中调用。成功时，它会提交优雅关服请求；运行时保存世界、卸载插件并停止 Remote 后，离开当前工作目录并递归删除整个房间目录。主服、模板目录和普通 `mcs_server_start_instance()` 实例调用时返回 `false`，不会删除任何文件。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 成功提交删除和关服请求返回 `true`；当前进程不是可删除动态房间时返回 `false`。 |

示例

```lua
local ok = mcs_server_delete_current_instance()
if not ok then
    mcs_server_send_message("current instance cannot be deleted", MCS_LOG_WARN)
end
```

#### mcs_server_query_status

服务端

描述

使用标准 Minecraft Status 协议查询 IPv4 服务端。该调用是同步的，因此插件不应在服务端 tick 回调中批量执行大量状态查询。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `address` | `string` | 目标 IPv4 地址，例如 `127.0.0.1`。 |
| `port` | `integer` | 目标 Minecraft 服务端口。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer, integer` | 成功时返回 `online_players, max_players`。 |
| `nil` | 连接失败、协议无效或状态 JSON 缺少人数时返回 `nil`。 |

示例

```lua
local online, max_players = mcs_server_query_status("127.0.0.1", 25565)
if online ~= nil then
    mcs_server_send_message(online .. "/" .. max_players .. " players online", MCS_LOG_INFO)
end
```

#### mcs_server_file_lock

服务端

描述

获取跨进程排他锁。成功后必须调用 `mcs_server_file_unlock(lock_id)` 释放；进程异常退出时操作系统也会自动释放锁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `path` | `string` | 锁文件路径。多个进程使用同一路径即可竞争同一把锁。 |
| `timeout_ms` | `integer` | 可选。等待锁的超时时间，单位毫秒。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回锁 ID。 |
| `nil` | 超时或出错。 |

示例

```lua
local lock_id = mcs_server_file_lock("/srv/oakmc/shared/economy.lock", 2000)
if lock_id ~= nil then
    -- 执行需要跨服互斥的逻辑。
    mcs_server_file_unlock(lock_id)
end
```

#### mcs_server_file_unlock

服务端

描述

释放 `mcs_server_file_lock` 成功获取的跨进程排他锁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `lock_id` | `integer` | `mcs_server_file_lock` 返回的锁 ID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 解锁成功返回 `true`，失败返回 `false`。 |

示例

```lua
local lock_id = mcs_server_file_lock("/srv/oakmc/shared/economy.lock", 2000)
if lock_id ~= nil then
    assert(mcs_server_file_unlock(lock_id))
end
```

#### mcs_command_register

服务端

描述

向原生服务端命令注册表加入一条命令。它会出现在 `help` 中，使用统一的 OP 权限校验，并通过 Brigadier 命令树发送给 Minecraft 客户端。执行 `reload-lua`、`reload` 或切换世界时，Lua 虚拟机关闭前会自动注销这些命令，不需要插件手动清理。

命令回调参数为 `context, args`。`args` 是从 1 开始、且不包含命令名的参数数组。`context.is_console`、`context.is_op` 和 `context.source` 始终存在；玩家执行时还会提供 `playername`/`username`、`uuid`、`entity_id` 与 `fd`。通过认证的远程命令使用控制台/OP 上下文。回调返回 `false` 表示本次参数无效，服务端会显示注册时提供的 usage；返回 `true` 或 `nil` 表示成功。命令名不能带 `/` 或空白，也不能覆盖内建命令或其他已注册命令。

`MCSCommandContext` 字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `is_console` | `boolean` | 命令来源是否为控制台上下文。本地控制台和通过认证的 Remote 命令都为 `true`。 |
| `is_op` | `boolean` | 命令来源是否具有 OP 权限；控制台和通过认证的 Remote 命令按 OP 上下文处理。 |
| `source` | `"console"` 或 `"player"` | 命令来源类型。控制台或 Remote 命令为 `"console"`；玩家在游戏内执行时为 `"player"`。 |
| `playername` | `string` | 可选。玩家执行命令时存在，表示玩家登录名。 |
| `username` | `string` | 可选。`playername` 的别名。 |
| `uuid` | `string` | 可选。玩家执行命令时存在，表示玩家 UUID。 |
| `entity_id` | `integer` | 可选。玩家执行命令时存在，表示玩家实体 ID。 |
| `fd` | `integer` | 可选。玩家执行命令时存在，表示玩家连接文件描述符。 |

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `command` | `string` | 命令名，不带 `/`，不能包含空白。 |
| `usage` | `string` | 用法文本，通常以命令名开头。 |
| `description` | `string` | 命令描述；不需要描述时可传 `nil`。 |
| `need_op` | `boolean` | 是否要求执行者具有 OP 权限。 |
| `callback` | `function` | 命令回调，签名为 `function(context, args)`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 注册成功返回 `true`，失败返回 `false`。 |

示例

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

assert(mcs_command_register(
    "luahello",
    "luahello [message]",
    "显示由 Lua 提供的问候",
    false,
    hello
))
```

#### mcs_chat_send_system_message

服务端

描述

服务端日志辅助函数的兼容别名。新代码如果要给玩家发送客户端可见消息，应优先使用明确受众的聊天 API。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `message` | `string` | 要输出的消息文本。 |
| `log_type` | `integer` | 可选。日志级别：`MCS_LOG_DEBUG` 调试信息，`MCS_LOG_INFO` 普通信息，`MCS_LOG_WARN` 警告，`MCS_LOG_ERROR` 错误。省略时由运行时使用默认日志级别。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_chat_send_system_message("server side log message", MCS_LOG_INFO)
```

#### mcs_chat_send_system_message_to_player

服务端

描述

向指定在线玩家发送普通系统聊天消息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收消息的在线玩家名。 |
| `message` | `string` | 要发送的消息文本。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_chat_send_system_message_to_player("Steve", "欢迎来到 OakMC")
```

#### mcs_chat_send_system_message_all_player

服务端

描述

向所有在线玩家广播普通系统聊天消息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `message` | `string` | 要广播的消息文本。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 广播成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_chat_send_system_message_all_player("服务器将在 5 分钟后重启")
```

#### mcs_remote_command_send

服务端

描述

向动态指定的 IPv4 地址和 Remote 监听端口发送签名指令。`target_id` 必须等于接收端配置的 `server-id`。发送端身份和集群密钥取自合并后的 Remote 运行配置；启动参数和 `OAKMC_REMOTE_SECRET` 可以覆盖本机 `remote.properties`。该文件不配置任何出站 peer。Token、nonce 和签名材料不会暴露给 Lua。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `target_id` | `string` | 目标服务端的 `server-id`。 |
| `address` | `string` | 目标 IPv4 地址。 |
| `port` | `integer` | 目标 Remote 监听端口。 |
| `command` | `string` | 要在目标服务端执行的命令。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean, string` | 对端接受时返回 `true, "OK"`。 |
| `boolean, string` | 对端明确拒绝时返回 `false, "ERR"`。 |
| `boolean, nil` | 连接失败或配置不存在时返回 `false, nil`。 |

示例

```lua
local ok, response = mcs_remote_command_send(
    "survival", "127.0.0.1", 25576, "say Hello from hub"
)
if not ok then
    mcs_server_send_message("remote command failed: " .. (response or "unavailable"), MCS_LOG_WARN)
end
```

#### mcs_remote_is_enabled

服务端

描述

获取当前进程是否具有合法且已启用的 Remote 配置。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | Remote 可用返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_remote_is_enabled() then
    mcs_server_send_message("remote bridge enabled", MCS_LOG_INFO)
end
```

### 2.2 方块

#### mcs_block_place

服务端

描述

修改服务端世界中的方块状态，并把本次 Block Update 只发送给 `playername`。需要广播给多人时，可以遍历 `mcs_player_list_info()` 后逐个调用。

`block_name_or_state_id` 既可以传原有整数 block state id，也可以传方块注册名，例如 `stone`、`minecraft:oak_stairs` 或 `Grass Block`。名称会映射到 Minecraft `26.1.2` 中该方块的默认状态。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收本次方块更新的在线玩家名。 |
| `x` | `number` | 方块 X 坐标。 |
| `y` | `number` | 方块 Y 坐标。 |
| `z` | `number` | 方块 Z 坐标。 |
| `block_name_or_state_id` | `string` 或 `integer` | 方块注册名或 Minecraft `26.1.2` block state id。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 放置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_block_place("Steve", 10, 64, 10, "minecraft:stone")
```

#### mcs_block_broadcast_update

服务端

描述

向已连接客户端广播单方块可视更新，但不修改服务端世界状态。适合在取消客户端行为后回滚显示。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `x` | `integer` | 方块 X 坐标。 |
| `y` | `integer` | 方块 Y 坐标。 |
| `z` | `integer` | 方块 Z 坐标。 |
| `block_name_or_state_id` | `string` 或 `integer` | 方块注册名或 Minecraft `26.1.2` block state id。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 广播成功返回 `true`，失败返回 `false`。 |

示例

```lua
local state = mcs_block_get_state(10, 64, 10)
mcs_block_broadcast_update(10, 64, 10, state)
```

#### mcs_block_get_state

服务端

描述

获取指定世界坐标处的 block state id。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `x` | `integer` | 方块 X 坐标。 |
| `y` | `integer` | 方块 Y 坐标。 |
| `z` | `integer` | 方块 Z 坐标。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 目标坐标处的 block state id。 |

示例

```lua
local state = mcs_block_get_state(10, 64, 10)
mcs_server_send_message("block state id: " .. state, MCS_LOG_INFO)
```

#### mcs_block_state_id_from_name

服务端

描述

根据方块注册名获取该方块的默认 block state id。名称可以带 `minecraft:` 命名空间，也可以省略命名空间。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `block_name` | `string` | 方块注册名，例如 `stone` 或 `minecraft:oak_stairs`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 名称有效时返回默认 block state id。 |
| `nil` | 方块名称未知。 |

示例

```lua
local state = mcs_block_state_id_from_name("minecraft:stone")
if state ~= nil then
    mcs_block_broadcast_update(10, 64, 10, state)
end
```

#### mcs_block_is_solid

服务端

描述

判断指定世界坐标处的方块是否为 solid 方块。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `x` | `integer` | 方块 X 坐标。 |
| `y` | `integer` | 方块 Y 坐标。 |
| `z` | `integer` | 方块 Z 坐标。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 目标坐标处方块为 solid 时返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_block_is_solid(10, 64, 10) then
    mcs_server_send_message("target block is solid", MCS_LOG_INFO)
end
```

#### mcs_block_state_is_solid

服务端

描述

判断指定方块名称或 block state id 是否为 solid 方块。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `block_name_or_state_id` | `string` 或 `integer` | 方块注册名或 Minecraft `26.1.2` block state id。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 对应方块状态为 solid 时返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_block_state_is_solid("minecraft:stone") then
    mcs_server_send_message("stone is solid", MCS_LOG_INFO)
end
```

#### mcs_block_set_break_animation

服务端

描述

只向 `playername` 对应客户端发送方块裂纹动画，不修改方块状态。`stage` 为 `0..9`，传 `-1` 清除；推进或清除同一处裂纹时应复用相同的 `animation_id`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收裂纹动画的在线玩家名。 |
| `animation_id` | `integer` | 裂纹动画 ID。同一处裂纹更新和清除时应复用同一个 ID。 |
| `x` | `integer` | 方块 X 坐标。 |
| `y` | `integer` | 方块 Y 坐标。 |
| `z` | `integer` | 方块 Z 坐标。 |
| `stage` | `integer` | 裂纹阶段，`0..9` 表示显示裂纹，`-1` 表示清除。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_block_set_break_animation("Steve", 123, 10, 64, 10, 5)
```

### 2.3 实体

#### mcs_entity_spawn

服务端

描述

生成一个客户端可见实体并广播给已初始化玩家。当前实现不提供完整的服务端实体 AI、tick 或持久化。`name_component` 可以是普通文本或 JSON Text Component；传入时，OakMC 会在 Add Entity 后立即发送自定义名称 metadata。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_type_id` | `integer` | Minecraft `26.1.2` 实体类型 id。 |
| `x` | `number` | 生成位置 X 坐标。 |
| `y` | `number` | 生成位置 Y 坐标。 |
| `z` | `number` | 生成位置 Z 坐标。 |
| `yaw` | `number` | 身体水平旋转角。 |
| `pitch` | `number` | 俯仰角。 |
| `head_yaw` | `number` | 头部水平旋转角。 |
| `data` | `integer` | 实体附加数据。 |
| `name_component` | `string` | 可选。普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回新分配的运行时 `entity_id`。 |
| `nil` | 生成失败。 |

示例

```lua
local entity_id = mcs_entity_spawn(1, 0.5, 65.0, 0.5, 0, 0, 0, 0, "Demo")
```

#### mcs_fake_player_add

服务端

描述

添加一个假玩家实体。它会先发送假玩家 Profile，再生成玩家实体，并保留传入的 `textures` value 和可选签名。`listed=false` 时 Profile 仍可用于加载皮肤，但假玩家不会显示在 Tab 中。假玩家不会计入真实在线玩家数量。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `username` | `string` | 假玩家的 GameProfile 名称。 |
| `uuid` | `string` | 假玩家 UUID。 |
| `x` | `number` | 生成位置 X 坐标。 |
| `y` | `number` | 生成位置 Y 坐标。 |
| `z` | `number` | 生成位置 Z 坐标。 |
| `yaw` | `number` | 身体水平旋转角。 |
| `pitch` | `number` | 俯仰角。 |
| `listed` | `boolean` | 是否显示在 Tab 玩家列表中。 |
| `texture_value` | `string` | Minecraft Profile 中 Base64 编码的 `textures` 属性值，不是皮肤图片 URL。 |
| `texture_signature` | `string` | 可选。`textures` 属性签名；无签名时可省略或传 `nil`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回假玩家运行时 `entity_id`。 |
| `nil` | 创建失败。 |

示例

```lua
local npc_id = mcs_fake_player_add(
    "GuideNPC",
    "12345678-1234-4234-8234-123456789abc",
    0.5, 65.0, 0.5,
    180.0, 0.0,
    false,
    profile_texture_value,
    profile_texture_signature
)
```

#### mcs_fake_player_set_name_visible

服务端

描述

设置假玩家头顶原始 GameProfile 名字是否可见。传 `false` 会把假玩家加入 `nameTagVisibility=never` 的 scoreboard Team；传 `true` 会删除该隐藏 Team 并恢复显示。状态会为之后加入或重新同步的玩家补发。它与 `listed` 相互独立，后者只控制 Tab 玩家列表。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 假玩家运行时实体 ID。 |
| `visible` | `boolean` | 是否显示头顶原始 GameProfile 名字。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_fake_player_set_name_visible(npc_id, false)
```

#### mcs_entity_spawn_with_velocity

服务端

描述

生成一个带初速度的客户端可见实体。初速度会直接写入 Add Entity 包，适合需要客户端从生成首 tick 就开始模拟的箭等投射物。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_type_id` | `integer` | Minecraft `26.1.2` 实体类型 id。 |
| `x` | `number` | 生成位置 X 坐标。 |
| `y` | `number` | 生成位置 Y 坐标。 |
| `z` | `number` | 生成位置 Z 坐标。 |
| `velocity_x` | `number` | 初速度 X 分量。 |
| `velocity_y` | `number` | 初速度 Y 分量。 |
| `velocity_z` | `number` | 初速度 Z 分量。 |
| `yaw` | `number` | 身体水平旋转角。 |
| `pitch` | `number` | 俯仰角。 |
| `head_yaw` | `number` | 头部水平旋转角。 |
| `data` | `integer` | 实体附加数据。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回新分配的运行时 `entity_id`。 |
| `nil` | 生成失败。 |

示例

```lua
local arrow_id = mcs_entity_spawn_with_velocity(95, 0.5, 65.0, 0.5, 0.0, 0.8, 0.0, 0, 0, 0, 0)
```

#### mcs_entity_set_custom_name

服务端

描述

广播实体 metadata，设置实体自定义名称以及是否在实体上方渲染名称。`name` 可以是普通文本或 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标运行时实体 ID。 |
| `name` | `string` | 普通文本或 JSON Text Component。 |
| `visible` | `boolean` | 是否在实体上方显示名称。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_entity_set_custom_name(entity_id, '{"text":"Guide","color":"gold"}', true)
```

#### mcs_entity_rotate

服务端

描述

为已经生成的实体广播可视旋转更新。`yaw`/`pitch` 通过 Entity Position Sync 更新身体，`head_yaw` 通过 Rotate Head 更新头部。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标运行时实体 ID。 |
| `x` | `number` | 实体 X 坐标。 |
| `y` | `number` | 实体 Y 坐标。 |
| `z` | `number` | 实体 Z 坐标。 |
| `yaw` | `number` | 身体水平旋转角。 |
| `pitch` | `number` | 俯仰角。 |
| `head_yaw` | `number` | 头部水平旋转角。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_entity_rotate(entity_id, 0.5, 65.0, 0.5, 180.0, 0.0, 180.0)
```

#### mcs_entity_move

服务端

描述

广播实体的位置、速度、旋转和着地状态。投射物等持续移动实体应使用此 API，让客户端在服务器 tick 之间进行平滑插值。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标运行时实体 ID。 |
| `x` | `number` | 实体 X 坐标。 |
| `y` | `number` | 实体 Y 坐标。 |
| `z` | `number` | 实体 Z 坐标。 |
| `velocity_x` | `number` | 速度 X 分量。 |
| `velocity_y` | `number` | 速度 Y 分量。 |
| `velocity_z` | `number` | 速度 Z 分量。 |
| `yaw` | `number` | 身体水平旋转角。 |
| `pitch` | `number` | 俯仰角。 |
| `head_yaw` | `number` | 头部水平旋转角。 |
| `on_ground` | `boolean` | 是否在地面上。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_entity_move(entity_id, 1.5, 65.0, 0.5, 0.1, 0.0, 0.0, 90.0, 0.0, 90.0, true)
```

#### mcs_entity_remove

服务端

描述

向所有已完成 Play 初始化的玩家发送 Remove Entities，并从运行时实体管理器注销该普通实体。假玩家还会同时清理客户端 Profile 缓存；真实连接玩家实体仍不允许通过此 API 删除。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 要移除的运行时实体 ID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_entity_remove(entity_id)
```

#### mcs_entity_get_info_by_id

服务端

描述

按运行时实体 ID 查询并返回通用实体快照。未知实体返回 `nil`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 运行时实体 ID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `MCSEntityInfo` | 查询成功时返回实体信息表。 |
| `nil` | 实体不存在。 |

示例

```lua
local info = mcs_entity_get_info_by_id(entity_id)
if info ~= nil then
    mcs_server_send_message("entity type: " .. info.entity_type_id, MCS_LOG_INFO)
end
```

#### mcs_hologram_create

服务端

描述

创建浮空字。浮空字使用原生 `minecraft:text_display` 实体，默认居中 billboard、始终朝向观察者，并开启文字阴影。文本支持普通字符串或 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `x` | `number` | 生成位置 X 坐标。 |
| `y` | `number` | 生成位置 Y 坐标。 |
| `z` | `number` | 生成位置 Z 坐标。 |
| `text` | `string` | 普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回 Text Display 的运行时 `entity_id`。 |
| `nil` | 创建失败。 |

示例

```lua
local id = mcs_hologram_create(0.5, 66.5, 0.5, '{"text":"OakMC","color":"gold","bold":true}')
```

#### mcs_hologram_set_text

服务端

描述

更新浮空字文本。只接受 Text Display 实体 ID；文本支持普通字符串或 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 浮空字 Text Display 运行时实体 ID。 |
| `text` | `string` | 新文本，支持普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_hologram_set_text(id, "欢迎！")
```

#### mcs_hologram_move

服务端

描述

移动浮空字。只接受 Text Display 实体 ID。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 浮空字 Text Display 运行时实体 ID。 |
| `x` | `number` | 目标 X 坐标。 |
| `y` | `number` | 目标 Y 坐标。 |
| `z` | `number` | 目标 Z 坐标。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移动成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_hologram_move(id, 0.5, 68.0, 0.5)
```

#### mcs_hologram_remove

服务端

描述

删除浮空字。只接受 Text Display 实体 ID；也可以使用通用的 `mcs_entity_remove` 删除浮空字。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 浮空字 Text Display 运行时实体 ID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 删除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_hologram_remove(id)
```

### 2.4 世界

#### mcs_world_update_weather

服务端

描述

直接更新发送给玩家的天气表现。天气持续时间倒计时和下一天气调度仍由 Play/world 内部实现维护，不放在 Lua 层。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `rain_level` | `number` | 雨量表现强度。 |
| `thunder_level` | `number` | 雷暴表现强度。 |
| `raining` | `boolean` | 是否处于下雨状态。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_world_update_weather(1.0, 0.0, true)
```

#### mcs_world_set_time

服务端

描述

向当前已经完成初始化的每个玩家各发送一次 Set Time 数据包，两个协议时间字段都使用传入的非负 tick 值。它不会保存或递增时间，不会启动定时器、修改 `level.dat`，也不会在玩家后来加入或切换世界时补发。只有需要再次更新客户端时间时才重新调用。它与控制标题动画时长的 `mcs_title_set_time` 无关。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `time` | `integer` | 客户端显示的世界时间，单位为 tick，必须是非负值。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_world_set_time(6000)
```

#### mcs_world_set_default_spawn_position

服务端

描述

设置指定维度的默认出生点。`x`、`y`、`z` 支持浮点坐标，玩家出生位置会保留小数；发送给客户端的默认出生方块坐标则按每个分量向下取整。成功写入存档后会触发 `MCS_EVENT_WORLD_SPAWN_SET`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `dimension_name` | `string` | 目标维度名称。 |
| `x` | `number` | 出生点 X 坐标。 |
| `y` | `number` | 出生点 Y 坐标。 |
| `z` | `number` | 出生点 Z 坐标。 |
| `yaw` | `number` | 出生朝向 yaw。 |
| `pitch` | `number` | 出生朝向 pitch。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_world_set_default_spawn_position("minecraft:overworld", 0.5, 65.0, 0.5, 0.0, 0.0)
```

当前没有公开的 `mcs_world_switch(...)` Lua 函数。活动存档通过控制台
`world load <name>` 切换，或修改 `server.properties` 中的 `level-name` 后执行
`reload`。两种方式都会保持在线连接，并触发上面描述的 Lua
`shutdown()`/`init()` 生命周期。

### 2.5 玩家查询

#### mcs_player_count

服务端

描述

获取当前在线玩家数量。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 当前在线玩家数量。 |

示例

```lua
local count = mcs_player_count()
mcs_server_send_message("online players: " .. count, MCS_LOG_INFO)
```

#### mcs_player_get_info_by_name

服务端

描述

按玩家名查询在线玩家信息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 在线玩家名。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `MCSPlayerInfo` | 查询成功时返回玩家信息表。 |
| `nil` | 玩家不存在或当前 API 无法表示该玩家。 |

示例

```lua
local info = mcs_player_get_info_by_name("Steve")
if info ~= nil then
    mcs_server_send_message(info.username .. " is online", MCS_LOG_INFO)
end
```

#### mcs_player_get_info_by_uuid

服务端

描述

按标准 UUID 查询在线玩家信息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `uuid` | `string` | 玩家标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `MCSPlayerInfo` | 查询成功时返回玩家信息表。 |
| `nil` | 玩家不存在或当前 API 无法表示该玩家。 |

示例

```lua
local info = mcs_player_get_info_by_uuid("12345678-1234-4234-8234-123456789abc")
```

#### mcs_player_get_info_by_fd

服务端

描述

按连接文件描述符查询在线玩家信息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `fd` | `integer` | 玩家连接文件描述符。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `MCSPlayerInfo` | 查询成功时返回玩家信息表。 |
| `nil` | 玩家不存在或当前 API 无法表示该玩家。 |

示例

```lua
local info = mcs_player_get_info_by_fd(fd)
```

#### mcs_player_list_info

服务端

描述

获取当前在线玩家信息列表。需要按玩家逐个发送客户端可见效果时，可以遍历该列表。

参数

无

返回值

| 数据类型 | 说明 |
| --- | --- |
| `table` | 玩家信息数组，数组元素为 `MCSPlayerInfo`。 |

示例

```lua
for _, player in ipairs(mcs_player_list_info()) do
    mcs_chat_send_system_message_to_player(player.username, "Hello")
end
```

`mcs_entity_get_info_by_id(entity_id)` 按实体 id 查询并返回 `MCSEntityInfo`，见上文实体分类。

`MCSPlayerInfo` 字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 玩家运行时实体 ID。 |
| `is_player` | `boolean` | 是否为真实玩家实体；玩家查询结果中通常为 `true`。 |
| `username` | `string` | 玩家登录用户名。 |
| `uuid` | `string` | 玩家 UUID。 |
| `fd` | `integer` | 玩家连接文件描述符。 |
| `play_initialized` | `boolean` | 玩家是否已经完成 Play 阶段初始化。 |
| `x` | `number` | 玩家当前位置 X 坐标。 |
| `y` | `number` | 玩家当前位置 Y 坐标。 |
| `z` | `number` | 玩家当前位置 Z 坐标。 |
| `yaw` | `number` | 玩家身体水平旋转角。 |
| `pitch` | `number` | 玩家俯仰角。 |
| `on_ground` | `boolean` | 客户端最近上报的是否在地面状态。 |
| `horizontal_collision` | `boolean` | 客户端最近上报的是否发生水平碰撞。 |
| `game_mode` | `integer` | 玩家当前游戏模式；`0` 生存、`1` 创造、`2` 冒险、`3` 旁观。 |
| `allow_flying` | `boolean` | 当前会话中是否授予生存/冒险模式额外飞行权限。 |
| `is_flying` | `boolean` | 客户端最近上报的实际飞行状态。 |
| `dimension_id` | `integer` | 玩家当前维度 ID。 |
| `health` | `number` | 玩家生命值。 |
| `armor` | `number` | 客户端可见护甲属性，用于护甲 HUD 显示。 |
| `food` | `integer` | 玩家饥饿值。 |
| `food_saturation` | `number` | 玩家饱和度。 |
| `selected_inventory_id` | `integer` | 当前选中的快捷栏槽位，范围 `0..8`。 |
| `awaiting_teleport` | `boolean` | 是否正在等待客户端确认一次服务端传送。 |
| `pending_teleport_id` | `integer` | 待确认传送 ID。 |
| `last_keep_alive_ms` | `integer` | 最近一次 KeepAlive 相关时间，单位毫秒。 |
| `pending_keep_alive_id` | `integer` | 待确认 KeepAlive ID。 |
| `is_jump` | `boolean` | 客户端最近上报的跳跃状态。 |
| `hidden` | `boolean` | 该玩家实体是否被全局隐藏；连接和 Tab 列表仍保留。 |
| `is_op` | `boolean` | 在线玩家当前会话是否拥有 OP 权限。 |

`MCSEntityInfo` 字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 运行时实体 ID。 |
| `kind` | `integer` | OakMC 内部实体类别。 |
| `entity_type_id` | `integer` | Minecraft `26.1.2` 实体类型 ID。 |
| `x` | `number` | 实体 X 坐标。 |
| `y` | `number` | 实体 Y 坐标。 |
| `z` | `number` | 实体 Z 坐标。 |
| `yaw` | `number` | 实体身体水平旋转角。 |
| `pitch` | `number` | 实体俯仰角。 |
| `head_yaw` | `number` | 实体头部水平旋转角。 |
| `data` | `integer` | 实体附加数据。 |
| `custom_name_visible` | `boolean` | 自定义名称是否可见。 |
| `custom_name` | `string` | 实体自定义名称；可能是普通文本或 JSON Text Component 字符串。 |

### 2.5.1 白名单与封禁

本分类中的 `identity` 可以是用户名或标准 UUID。修改操作会持久化到与内建命令相同的 JSON 文件。玩家封禁会踢出匹配的在线玩家；IP 封禁会尽力踢出当前使用该 IPv4 地址的全部在线玩家，并拒绝该地址后续的新连接。

#### mcs_whitelist_add

服务端

描述

把玩家身份加入白名单。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` | `string` | 玩家用户名或标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 添加成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_whitelist_add("Steve")
```

#### mcs_whitelist_remove

服务端

描述

从白名单移除玩家身份。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` | `string` | 玩家用户名或标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_whitelist_remove("Steve")
```

#### mcs_whitelist_contains

服务端

描述

检查玩家身份是否在白名单中。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` | `string` | 玩家用户名或标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 在白名单中返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_whitelist_contains("Steve") then
    mcs_server_send_message("Steve is whitelisted", MCS_LOG_INFO)
end
```

#### mcs_ban_add

服务端

描述

添加玩家封禁。可以只传用户名或 UUID，也可以同时传 `username, uuid`。封禁会持久化，并踢出匹配的在线玩家。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` / `username` | `string` | 玩家用户名或标准 UUID；双参数形式下表示用户名。 |
| `uuid` | `string` | 可选。双参数形式下的玩家 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 添加成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_ban_add("Steve")
mcs_ban_add("Steve", "12345678-1234-4234-8234-123456789abc")
```

#### mcs_ban_remove

服务端

描述

移除玩家封禁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` | `string` | 玩家用户名或标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_ban_remove("Steve")
```

#### mcs_ban_contains

服务端

描述

检查玩家身份是否已被封禁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `identity` | `string` | 玩家用户名或标准 UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 已封禁返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_ban_contains("Steve") then
    mcs_server_send_message("Steve is banned", MCS_LOG_INFO)
end
```

#### mcs_ban_ip_add

服务端

描述

添加 IP 封禁，并尽力踢出当前使用该 IPv4 地址的全部在线玩家。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `ip` | `string` | IPv4 地址。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 添加成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_ban_ip_add("192.168.1.10")
```

#### mcs_ban_ip_remove

服务端

描述

移除 IP 封禁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `ip` | `string` | IPv4 地址。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_ban_ip_remove("192.168.1.10")
```

#### mcs_ban_ip_contains

服务端

描述

检查 IPv4 地址是否已被封禁。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `ip` | `string` | IPv4 地址。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 已封禁返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_ban_ip_contains("192.168.1.10") then
    mcs_server_send_message("IP is banned", MCS_LOG_INFO)
end
```

### 2.6 玩家控制

#### mcs_player_kick

服务端

描述

踢出指定在线玩家。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 踢出成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_kick("Steve")
```

#### mcs_player_tp_by_name

服务端

描述

传送指定在线玩家到目标坐标和朝向。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `x` | `number` | 目标 X 坐标。 |
| `y` | `number` | 目标 Y 坐标。 |
| `z` | `number` | 目标 Z 坐标。 |
| `yaw` | `number` | 目标 yaw。 |
| `pitch` | `number` | 目标 pitch。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 传送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_tp_by_name("Steve", 0.5, 65.0, 0.5, 0.0, 0.0)
```

#### mcs_player_sync_position_with_velocity

服务端

描述

同步玩家位置、速度和朝向。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `x` / `y` / `z` | `number` | 目标坐标。 |
| `velocity_x` / `velocity_y` / `velocity_z` | `number` | 速度分量。 |
| `yaw` | `number` | 目标 yaw。 |
| `pitch` | `number` | 目标 pitch。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 同步成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_sync_position_with_velocity("Steve", 0.5, 65.0, 0.5, 0.0, 0.4, 0.0, 0.0, 0.0)
```

#### mcs_player_transfer

服务端

描述

向客户端发送 transfer 包，让客户端重新建立一条 Minecraft 连接。它与在现有 Velocity 连接内切换后端不是同一机制。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `host` | `string` | 目标服务器地址。 |
| `port` | `integer` | 可选。目标服务器端口。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_transfer("Steve", "127.0.0.1", 25566)
```

#### mcs_player_send_custom_payload

服务端

描述

发送 Play 阶段 Custom Payload。`payload` 是二进制安全的 Lua 字符串，OakMC 不添加内部长度或解释其内容；单条 payload 最大为 32 KiB。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `channel` | `string` | 自定义 payload 频道。 |
| `payload` | `string` | 二进制安全 payload。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_send_custom_payload("Steve", "oakmc:debug", "hello")
```

#### mcs_player_set_gamemode

服务端

描述

设置玩家游戏模式。`gamemode` 可以使用数值 `MCS_GAMEMODE_*` 常量，也可以使用字符串 `"survival"`、`"creative"`、`"adventure"` 或 `"spectator"`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `gamemode` | `integer` 或 `string` | 目标游戏模式。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_gamemode("Steve", "creative")
```

#### mcs_player_set_custom_name

服务端

描述

设置 Player Info/tab 路径使用的 profile name。值必须是普通 profile-name 字符串，不是 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `name` | `string` | 新 profile name。 |
| `visible` | `boolean` | 是否立即广播 Player Info 更新。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_custom_name("Steve", "ServerPlayer", true)
```

#### mcs_player_set_custom_prefix_name

服务端

描述

设置世界内玩家名牌前缀。prefix 支持普通文本或 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `prefix` | `string` | 名牌前缀文本或 JSON Text Component。 |
| `visible` | `boolean` | 是否显示该前缀；`false` 会删除自动生成的 team。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_custom_prefix_name("Steve", '{"text":"[OakMC] ","color":"gold"}', true)
```

#### mcs_player_hide

服务端

描述

隐藏目标玩家实体。省略 `viewername` 时对其他客户端隐藏；传入 `viewername` 时只让指定观察者看不到目标玩家。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 被隐藏的目标玩家名。 |
| `viewername` | `string` | 可选。只对该观察者隐藏目标玩家。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 隐藏成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_hide("Steve")
mcs_player_hide("Steve", "Alex")
```

#### mcs_player_show

服务端

描述

恢复目标玩家实体显示。省略 `viewername` 时对其他客户端恢复；传入 `viewername` 时只向指定观察者恢复目标玩家。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 需要恢复显示的目标玩家名。 |
| `viewername` | `string` | 可选。只对该观察者恢复显示。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 恢复成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_show("Steve")
mcs_player_show("Steve", "Alex")
```

#### mcs_player_set_op

服务端

描述

授予或撤销在线玩家当前会话的 OP 权限。变更会立即生效并向该玩家重发命令树，但不会在玩家重连后保留。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `is_op` | `boolean` | 是否授予 OP 权限。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`；玩家不在线或命令树发送失败时返回 `false`。 |

示例

```lua
mcs_player_set_op("Steve", true)
```

#### mcs_player_get_gamemode

服务端

描述

获取玩家当前游戏模式。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `integer` | 成功时返回 gamemode id。 |
| `nil` | 玩家不存在或查询失败。 |

示例

```lua
local gamemode = mcs_player_get_gamemode("Steve")
```

#### mcs_player_update_health

服务端

描述

更新玩家生命值、饥饿值和饱和度。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `health` | `number` | 生命值。 |
| `food` | `integer` | 饥饿值。 |
| `food_saturation` | `number` | 饱和度。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_update_health("Steve", 20.0, 20, 5.0)
```

#### mcs_player_set_armor_value

服务端

描述

设置客户端可见的护甲值，用于护甲 HUD 显示。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `armor` | `number` | 客户端可见护甲值。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_armor_value("Steve", 10)
```

#### mcs_player_set_experience

服务端

描述

更新经验 HUD。`progress` 是经验条填充比例，范围为 `0.0..1.0`；`level` 和 `total_experience` 必须是非负整数。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `progress` | `number` | 经验条填充比例，范围 `0.0..1.0`。 |
| `level` | `integer` | 经验等级显示数字。 |
| `total_experience` | `integer` | 总经验值。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_experience("Steve", 0.5, 10, 100)
```

#### mcs_player_set_allow_flying

服务端

描述

设置生存或冒险模式玩家当前在线会话的额外飞行权限。传 `false` 会立即撤销权限并停止飞行；创造和旁观模式自带的飞行能力不受 `false` 影响。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `allow_flying` | `boolean` | 是否允许飞行。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_allow_flying("Steve", true)
```

#### mcs_player_set_flying_speed

服务端

描述

设置玩家客户端飞行速度。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `flying_speed` | `number` | 飞行速度。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_flying_speed("Steve", 0.05)
```

#### mcs_player_set_held_item_display

服务端

描述

按已登记的 `entity_id` 发送手持物可视显示。它只控制可视装备，不修改真实连接玩家的服务端背包。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标实体 ID。 |
| `hand` | `integer` | 手，`0` 主手，`1` 副手。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `count` | `integer` | 可选。数量；传 `0` 或空气可清除。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_held_item_display(entity_id, 0, 895, 1)
```

#### mcs_player_set_equipment_display

服务端

描述

只向指定 `viewer_name` 发送目标实体完整装备槽显示。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `viewer_name` | `string` | 接收可视装备包的玩家名。 |
| `entity_id` | `integer` | 目标实体 ID。 |
| `equipment_slot` | `integer` | 装备槽：`0` 主手、`1` 副手、`2` 靴子、`3` 护腿、`4` 胸甲、`5` 头盔、`6` 身体装备。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `count` | `integer` | 可选。数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_equipment_display("Steve", entity_id, 5, 1, 1)
```

#### mcs_player_set_equipment_display_for_others

服务端

描述

向除实体所有者之外的已初始化客户端发送目标实体装备显示，适合广播真实玩家主手，避免延迟包覆盖玩家自己的滚轮选择。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标实体 ID。 |
| `equipment_slot` | `integer` | 装备槽 ID。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `count` | `integer` | 可选。数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_equipment_display_for_others(entity_id, 0, 895, 1)
```

#### mcs_player_set_equipment_display_for_all

服务端

描述

向所有已初始化客户端发送目标实体装备显示，包括实体所有者。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 目标实体 ID。 |
| `equipment_slot` | `integer` | 装备槽 ID。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `count` | `integer` | 可选。数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_equipment_display_for_all(entity_id, 5, 1, 1)
```

#### mcs_player_set_bow_animation

服务端

描述

向指定玩家发送 Living Entity 持续使用物品姿势，用于开始或停止拉弓动画。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收动画的玩家名。 |
| `entity_id` | `integer` | 播放姿势的实体 ID。 |
| `pulling` | `boolean` | 是否开始拉弓；`false` 表示结束。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_bow_animation("Steve", entity_id, true, 0)
```

#### mcs_player_set_bow_animation_for_others

服务端

描述

向除实体所有者之外的已初始化客户端发送拉弓动画。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放姿势的实体 ID。 |
| `pulling` | `boolean` | 是否开始拉弓；`false` 表示结束。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_bow_animation_for_others(entity_id, true, 0)
```

#### mcs_player_set_bow_animation_for_all

服务端

描述

向所有已初始化客户端发送拉弓动画，包括实体所有者。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放姿势的实体 ID。 |
| `pulling` | `boolean` | 是否开始拉弓；`false` 表示结束。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_bow_animation_for_all(entity_id, true, 0)
```

#### mcs_player_swing_hand

服务端

描述

向指定玩家发送放置方块和破坏方块共用的挥手动画。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收动画的玩家名。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_swing_hand("Steve", 0)
```

#### mcs_player_swing_hand_for_others

服务端

描述

向除实体所有者之外的已初始化客户端发送挥手动画。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放动画的实体 ID。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_swing_hand_for_others(entity_id, 0)
```

#### mcs_player_swing_hand_for_all

服务端

描述

向所有已初始化客户端发送挥手动画，包括实体所有者。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放动画的实体 ID。 |
| `hand` | `integer` | 可选。`0` 主手，`1` 副手。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_swing_hand_for_all(entity_id, 0)
```

#### mcs_player_hurt_animation_for_others

服务端

描述

向除实体所有者之外的已初始化客户端发送受击动画。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放受击动画的实体 ID。 |
| `yaw` | `number` | 受击动画方向。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_hurt_animation_for_others(entity_id, 0.0)
```

#### mcs_player_hurt_animation_for_all

服务端

描述

向所有已初始化客户端发送受击动画，包括实体所有者。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `entity_id` | `integer` | 播放受击动画的实体 ID。 |
| `yaw` | `number` | 受击动画方向。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_hurt_animation_for_all(entity_id, 0.0)
```

`gamemode` 可以使用数值 `MCS_GAMEMODE_*` 常量，也可以使用字符串
`"survival"`、`"creative"`、`"adventure"` 或 `"spectator"`。

`mcs_player_transfer(playername, host, port)` 会向客户端发送 transfer 包；
`port` 可省略。它会让客户端重新建立一条 Minecraft 连接，与在现有 Velocity
连接内切换后端不是同一机制。

`mcs_player_send_custom_payload(playername, channel, payload)` 发送 Play 阶段
Custom Payload。`payload` 是二进制安全的 Lua 字符串，OakMC 不添加内部长度
或解释其内容；频道协议自行定义 payload 格式。单条 payload 最大为 32 KiB。

可选的 OakMC Velocity Bridge 在这套通用 API 上实现 Velocity 内部切服。
代理端必须安装兼容的桥接插件；它会消费控制消息，不会让消息到达 Minecraft
客户端。应用插件可以编码以下频道协议：

```text
channel = oakmc:proxy_transfer

version:u8 (=1)
server_name:u16大端长度 + UTF-8
host:u16大端长度 + UTF-8
port:u16大端
```

Velocity `server_name` 应与保持唯一的 OakMC 子进程实例名分离。只有所有动态目标
都位于同一个固定主机时，才适合仅根据端口生成名称。多目标主机部署如果可能复用
相同端口，必须加入稳定的主机标识，避免两个不同地址共用一个 Velocity 注册键。
encoder、目标选择和后端生命周期策略均由应用插件负责。完整桥接协议见
`integrations/velocity-bridge/README.zh-CN.md`。

`mcs_player_set_experience` 用于更新经验 HUD。`progress` 是经验条填充比例，
范围为 `0.0..1.0`；`level` 是经验条上方显示的等级数字；`level` 和
`total_experience` 必须是非负整数。

`mcs_player_set_allow_flying(playername, true)` 可让生存或冒险模式玩家通过
双击跳跃键起飞，而不改变其游戏模式；传 `false` 会立即撤销权限并停止飞行。
创造和旁观模式自带的飞行能力不受 `false` 影响。该设置只在当前在线会话有效。
玩家 info 中的 `allow_flying` 表示该额外权限，`is_flying` 表示客户端最近上报的
实际飞行状态。

两个玩家名称函数面向不同的客户端显示位置：

- `mcs_player_set_custom_name` 会保存传入名称；当 `visible` 为 `true` 时，
  使用该 profile name 重新广播 Player Info entry。这是 Player Info/tab 路径，
  值必须是普通 profile-name 字符串而不是 JSON Text Component，并且必须符合
  协议用户名长度限制。`visible` 为 `false` 时只保存值，不发送 Player Info 更新。
- `mcs_player_set_custom_prefix_name` 会发送实体自定义名称 metadata，并使用
  scoreboard team prefix 修改世界内玩家名牌。prefix 支持普通文本或 JSON Text
  Component；`visible == false` 时会从 viewer 中删除自动生成的 team。

两个函数都不会修改 `mcs_player_get_info_by_name(...)` 等服务端查询所使用的
登录用户名。

`mcs_player_hide(playername)` 会向其他已完成 Play 初始化的客户端发送该玩家的
Remove Entities，并持续抑制该玩家后续的实体生成和移动广播。玩家连接、
PlayerManager 记录、背包、区块加载和 Tab 列表都保持不变。
`mcs_player_show(playername)` 会清除隐藏状态，并向其他客户端重新发送玩家实体、
皮肤部件 metadata 和自定义名牌状态。两个函数重复调用都是安全的。

传入 `viewername` 时只改变该观察者看到的实体：
`mcs_player_hide(target, viewer)` 仅让 `viewer` 看不到 `target`，
`mcs_player_show(target, viewer)` 仅向 `viewer` 恢复 `target`。这项定向关系会在
当前在线会话内持续过滤后续移动广播和实体重同步，但不会修改目标玩家的全局
`hidden` 字段或 Tab 列表。

`mcs_player_set_op(playername, is_op)` 用于授予或撤销在线玩家当前会话的 OP
权限。变更会立即生效并向该玩家重发命令树，但不会在玩家重连后保留。玩家不在线
或命令树发送失败时返回 `false`。

玩家可视动作接口用于发送客户端可见的实体状态：

- `mcs_player_set_held_item_display` 按已登记的 `entity_id` 发送 `Set Equipment`。
  `hand=0` 表示主手，`hand=1` 表示副手。实体管理器会保存显示物品并在玩家稍后
  加入时恢复，但不会修改真实连接玩家的服务端背包；传 `count=0` 或空气可清除。
- `mcs_player_set_equipment_display` 只向指定 `viewer_name` 发送完整装备槽：`0` 主手、`1` 副手、`2` 靴子、
  `3` 护腿、`4` 胸甲、`5` 头盔、`6` 身体装备。装备会广播给当前玩家并为后来加入
  的玩家恢复；它只控制可视装备，不修改真实背包或自动计算护甲减伤。
- `mcs_player_set_equipment_display_for_others` 使用相同的装备槽，但不会把数据包发给
  实体本人，适合广播真实玩家的主手，避免延迟包覆盖玩家自己的滚轮选择。
- `mcs_player_set_equipment_display_for_all` 使用相同的装备槽并发送给所有当前玩家，
  包括实体本人，适合钻石甲等本人也需要看到的装备。
- `mcs_player_set_bow_animation` 开始或停止 Living Entity 的持续使用物品姿势。
  `playername` 是接收者，`entity_id` 是播放姿势的实体。需要广播时遍历
  `mcs_player_list_info()` 逐个调用；传 `pulling=false` 会结束拉弓姿势。
  `_for_others` 和 `_for_all` 分别按统一受众规则发送。
- `mcs_player_swing_hand` 发送放置方块和破坏方块共用的挥手动画。完整破坏效果
  可与 `mcs_block_set_break_animation` 组合；放置效果可与 `mcs_block_place` 或
  `mcs_block_broadcast_update` 组合。显式广播请使用对应的 `_for_others` 或
  `_for_all` 版本。

```lua
local entity_id = mcs_player_get_info_by_name("Steve").entity_id
mcs_player_set_held_item_display(entity_id, 0, 895, 1) -- 26.1.2 弓物品 ID
mcs_player_set_bow_animation("Steve", entity_id, true, 0)
mcs_player_swing_hand("Steve", 0)
mcs_block_set_break_animation("Steve", 123, 10, 64, 10, 5)
```

### 2.7 背包

#### mcs_player_set_inventory_item

服务端

描述

直接设置玩家一个已跟踪的背包槽位。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 背包槽位，`0..8` 为快捷栏，`9..35` 为背包主体。 |
| `item_id_or_name` | `integer` 或 `string` | Minecraft `26.1.2` 物品 ID 或物品注册名。 |
| `count` | `integer` | 物品数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_inventory_item("Steve", 0, "minecraft:diamond_sword", 1)
```

#### mcs_player_give_item

服务端

描述

向玩家发放物品。发放前会触发 `MCS_EVENT_PLAYER_RECEIVE_ITEM`，Lua handler 可以取消发放，或在默认 handler 更新槽位并发送背包同步包之前改写事件字段。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 目标背包槽位。 |
| `item_id_or_name` | `integer` 或 `string` | Minecraft `26.1.2` 物品 ID 或物品注册名。 |
| `count` | `integer` | 物品数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发放成功返回 `true`，失败或被事件取消返回 `false`。 |

示例

```lua
mcs_player_give_item("Steve", 0, "diamond_sword", 1, '{"text":"奖励","color":"gold"}')
```

#### mcs_player_get_inventory_info

服务端

描述

查询玩家指定背包槽位的信息。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 背包槽位。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `MCSInventoryInfo` | 查询成功时返回槽位信息。 |
| `nil` | 玩家或槽位不存在。 |

示例

```lua
local info = mcs_player_get_inventory_info("Steve", 0)
```

#### mcs_player_inventory_is_item

服务端

描述

判断玩家指定背包槽位是否为非空物品槽位。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 背包槽位。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 槽位非空返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_player_inventory_is_item("Steve", 0) then
    mcs_server_send_message("Steve has selected item", MCS_LOG_INFO)
end
```

#### mcs_player_inventory_is_block

服务端

描述

判断玩家指定背包槽位是否为方块物品。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 背包槽位。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 槽位物品属于方块物品返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_player_inventory_is_block("Steve", 0) then
    mcs_server_send_message("selected item is a block", MCS_LOG_INFO)
end
```

#### mcs_player_inventory_is_food

服务端

描述

判断玩家指定背包槽位是否为食物。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `inventory_id` | `integer` | 背包槽位。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 槽位物品为食物返回 `true`，否则返回 `false`。 |

示例

```lua
if mcs_player_inventory_is_food("Steve", 0) then
    mcs_server_send_message("selected item is food", MCS_LOG_INFO)
end
```

`mcs_player_set_inventory_item` 会直接设置一个已跟踪的背包槽位。
`mcs_player_give_item` 会先发出 `MCS_EVENT_PLAYER_RECEIVE_ITEM`；Lua handler
可以取消发放，或者在默认 handler 更新槽位并发送背包同步包之前改写
`event.inventory_id`、`event.item_id`、`event.count`、`event.nbt_data` 和
`event.source`。当前运行时跟踪玩家背包槽位 `0..35`：`0..8` 是快捷栏，
`9..35` 是背包主体；`selected_inventory_id` 仍只允许快捷栏范围 `0..8`。
`item_id_or_name` 可以是 Minecraft 26.1.2 的数字物品 ID，也可以是
`diamond_sword`、`minecraft:diamond_sword` 这样的物品注册名。

`nbt_data` 是可选参数，可以传普通文本、`{CustomName:'测试'}` 或直接传
JSON Text Component，例如 `{"text":"测试","color":"gold","bold":true}`。
OakMC 会把它写成 Minecraft 26.1.2 的 `minecraft:custom_name` Text Component
compound。ItemStack component 使用协议的直接 component codec，不插入额外的
单 component payload 长度。传 `nil` 或 `""` 时 added/removed component list
保持为空。其他 NBT tag 尚未实现；不支持的输入会被拒绝，而不是作为无效
ItemStack 发给客户端。

`mcs_player_get_inventory_info(...)` 失败时返回 `nil`，成功时返回以下字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `inventory_id` | `integer` | 背包槽位 ID。当前运行时跟踪 `0..35`：`0..8` 是快捷栏，`9..35` 是背包主体。 |
| `used` | `boolean` | 槽位是否被运行时跟踪并处于已使用状态。 |
| `is_item` | `boolean` | 槽位是否为非空物品槽位。 |
| `is_block` | `boolean` | 槽位物品是否属于方块物品。 |
| `is_food` | `boolean` | 槽位物品是否属于食物。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `block_state_id` | `integer` | 如果物品可映射为方块物品，这里是对应 block state id；不可用时为运行时默认值。 |
| `count` | `integer` | 槽位中的物品数量。 |

`is_item` 表示槽位非空。`is_block` 使用本地 Minecraft `26.1.2` `BlockItem`
注册表判断，因此即使 OakMC 尚未实现所有特殊放置路径，它仍能判断手持物是否
属于方块物品。`is_food` 使用本地 Minecraft `26.1.2` food/component 列表；
例如 wheat 和 egg 是物品，但不是食物。

右键事件示例：

```lua
mcs_event_register(MCS_EVENT_BLOCK_PLACE, 100, function(event)
    local player = mcs_player_get_info_by_name(event.playername)
    if player == nil then
        return
    end

    local info = mcs_player_get_inventory_info(event.playername, player.selected_inventory_id)
    if info ~= nil and info.is_food then
        print("player right-clicked with food item_id=" .. info.item_id)
    end
end)
```

### 2.8 效果与伤害

#### mcs_player_set_effect

服务端

描述

给玩家设置状态效果。Lua effect 时长使用面向用户的秒数，与内建 `effect` 命令一致；无限时长使用字符串 `"infinite"`。`amplifier` 是协议 amplifier，因此从 `0` 开始。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `effect_id_or_name` | `integer` 或 `string` | 效果 ID、效果常量或效果名称。 |
| `amplifier` | `integer` | 协议 amplifier，例如 Speed II 使用 `1`。 |
| `duration_or_infinite` | `number` 或 `string` | 持续秒数，或字符串 `"infinite"`。 |
| `flags` | `string` | 效果显示标记，例如 `"icon"` 或 `"particles,icon"`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_effect("Steve", "speed", 1, 30, "icon")
mcs_player_set_effect("Steve", "night_vision", 0, "infinite", "particles,icon")
```

#### mcs_player_apply_damage

服务端

描述

对目标实体或玩家应用伤害。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `target` | `string` 或 `integer` | 目标玩家名或目标实体 ID。 |
| `source_entity_id` | `integer` | 伤害来源实体 ID。 |
| `amount` | `number` | 伤害数值。 |
| `damage_cause` | `integer` 或 `string` | 伤害原因。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 伤害应用成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_apply_damage("Steve", 0, 4.0, "generic")
```

Lua effect 时长使用面向用户的秒数，与内建 `effect` 命令一致。无限时长使用
字符串 `"infinite"`。

示例：

```lua
mcs_player_set_effect("Steve", "speed", 1, 30, "icon")
mcs_player_set_effect("Steve", MCS_EFFECT_SPEED, 254, 60, "icon")
mcs_player_set_effect("Steve", "night_vision", 0, "infinite", "particles,icon")
```

effect `amplifier` 是协议 amplifier，因此从 `0` 开始。例如 Speed II 使用
amplifier `1`，Speed 255 使用 amplifier `254`。

### 2.9 Screen 与 BossBar

#### mcs_player_open_book

服务端

描述

强制打开 writable book GUI。玩家没有手持书本时也可以打开；服务端跟踪的背包不会被修改。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `pages` | `string` 或 `table` | 可选。单页字符串，或包含 `1..100` 个字符串的页数组。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_book("Steve", "欢迎来到 OakMC！")
```

#### mcs_player_open_written_book

服务端

描述

打开只读成书 GUI，标题和作者都默认为 `OakMC`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `pages` | `string` 或 `table` | 单页字符串，或页数组。普通 written-book API 会把每页严格当作字面文本。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_written_book("Steve", {"只读第一页", "只读第二页"})
```

#### mcs_player_open_book_with_title

服务端

描述

打开只读成书 GUI，并自定义书名；作者仍默认为 `OakMC`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `title` | `string` | 书名，限制为 `1..32` 个 UTF-8 字符且最多 128 字节。 |
| `pages` | `string` 或 `table` | 单页字符串或页数组。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_book_with_title("Steve", "服务器指南", {"欢迎", "规则"})
```

#### mcs_player_open_book_with_author

服务端

描述

打开只读成书 GUI，并自定义作者；书名仍默认为 `OakMC`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `author` | `string` | 作者，限制为 `1..16` 个 UTF-8 字符且最多 64 字节。 |
| `pages` | `string` 或 `table` | 单页字符串或页数组。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_book_with_author("Steve", "Latos", "作者是 Latos")
```

#### mcs_player_open_book_components

服务端

描述

打开只读成书 GUI，页面允许普通文本或 JSON Text Component，可设置样式以及客户端支持的点击/悬停事件。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `title` | `string` | 书名。 |
| `author` | `string` | 作者。 |
| `page_components` | `string` 或 `table` | 单页 Text Component 字符串或页数组。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_book_components("Steve", "OakMC 指南", "OakMC", {
    '{"text":"欢迎","color":"gold","bold":true}',
})
```

#### mcs_player_open_screen

服务端

描述

发送 clientbound Open Window/Open Screen 包，只打开客户端 GUI；槽位内容和点击处理分别由 container 包和事件负责。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `window_id` | `integer` | 服务端选择的 container id。 |
| `inventory_type` | `integer` | 当前 Minecraft 版本的协议 menu type registry id。 |
| `title` | `string` | GUI 标题，支持普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 打开成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_open_screen("Steve", 1, 0, "OakMC Menu")
```

#### mcs_player_set_screen_slot

服务端

描述

发送 clientbound Container Set Slot，更新已经打开的 GUI 中一个槽位，不修改玩家已跟踪背包。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `container_id` | `integer` | 与 `mcs_player_open_screen` 使用相同的 container id。 |
| `state_id` | `integer` | container state id；简单纯可视菜单可以从 `0` 开始。 |
| `slot_id` | `integer` | GUI 槽位 ID。 |
| `item_id` | `integer` | Minecraft `26.1.2` 物品 ID。 |
| `count` | `integer` | 物品数量。 |
| `nbt_data` | `string` | 可选。物品自定义名称输入。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_set_screen_slot("Steve", 1, 0, 0, 1, 1, nil)
```

#### mcs_player_boss_bar_add

服务端

描述

向指定玩家添加 BossBar。BossBar 标题支持普通文本或 JSON Text Component。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `uuid` | `string` | BossBar UUID，例如 `00000000-0000-4000-8000-000000000001`。 |
| `title` | `string` | BossBar 标题。 |
| `health` | `number` | 进度值，范围 `0.0..1.0`。 |
| `color` | `integer` | `MCS_BOSS_BAR_COLOR_*` 常量。 |
| `dividers` | `integer` | `MCS_BOSS_BAR_DIVISION_*` 常量。 |
| `flags` | `integer` | `MCS_BOSS_BAR_FLAG_*` 按位组合。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 添加成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_boss_bar_add("Steve", "00000000-0000-4000-8000-000000000001", "Boss", 1.0, MCS_BOSS_BAR_COLOR_PURPLE, MCS_BOSS_BAR_DIVISION_NONE, 0)
```

#### mcs_player_boss_bar_remove

服务端

描述

从指定玩家客户端移除 BossBar。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `uuid` | `string` | BossBar UUID。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_boss_bar_remove("Steve", "00000000-0000-4000-8000-000000000001")
```

#### mcs_player_boss_bar_update_health

服务端

描述

更新指定 BossBar 的进度值。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `uuid` | `string` | BossBar UUID。 |
| `health` | `number` | 进度值，范围 `0.0..1.0`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_boss_bar_update_health("Steve", "00000000-0000-4000-8000-000000000001", 0.5)
```

#### mcs_player_boss_bar_update_style

服务端

描述

更新指定 BossBar 的颜色和分段样式。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `uuid` | `string` | BossBar UUID。 |
| `color` | `integer` | `MCS_BOSS_BAR_COLOR_*` 常量。 |
| `dividers` | `integer` | `MCS_BOSS_BAR_DIVISION_*` 常量。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_boss_bar_update_style("Steve", "00000000-0000-4000-8000-000000000001", MCS_BOSS_BAR_COLOR_RED, MCS_BOSS_BAR_DIVISION_10)
```

#### mcs_player_boss_bar_update_flags

服务端

描述

更新指定 BossBar 的 flags。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `uuid` | `string` | BossBar UUID。 |
| `flags` | `integer` | `MCS_BOSS_BAR_FLAG_*` 按位组合。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_boss_bar_update_flags("Steve", "00000000-0000-4000-8000-000000000001", MCS_BOSS_BAR_FLAG_DARKEN_SKY)
```

`mcs_player_open_book` 会在玩家没有手持书本时也强制打开书本 GUI。可选的
`pages` 可以是一个字符串，也可以是包含 `1..100` 个字符串的数组。每页最多
1024 个 UTF-8 字符且编码后最多 4096 字节。OakMC 先保存当前选中的主手槽位，
只向该客户端临时显示带 `minecraft:writable_book_content` 的 writable book，
然后发送 protocol 775 Open Book 包，并在短暂延迟后恢复原槽位。服务端跟踪
的背包不会被修改。

四个 written-book API 会打开只读的成书 GUI。`pages` 和 `page_components`
都可以是一个字符串，或包含 `1..100` 个字符串的数组；页数、字符数和字节数
限制与 `mcs_player_open_book` 相同。`mcs_player_open_written_book` 的标题和作者
都默认为 `OakMC`；with-title / with-author 版本只替换指定字段，另一个字段仍为
`OakMC`。标题限制为 `1..32` 个 UTF-8 字符且最多 128 字节，作者限制为
`1..16` 个 UTF-8 字符且最多 64 字节。

普通 written-book API 会把每页严格当作字面文本，因此看起来像 JSON 的字符串
也会原样显示。`mcs_player_open_book_components` 则允许普通文本或 JSON Text
Component，可设置样式以及客户端支持的点击/悬停事件。所有书本 API 都复用
“客户端临时主手 ItemStack + 延迟 tick 恢复”流程，不会修改服务端跟踪背包。

`mcs_player_open_screen` 发送 clientbound Open Window/Open Screen 包。
`window_id` 是服务端选择的 container id，`inventory_type` 是当前 Minecraft
版本的协议 menu type registry id。此函数只打开客户端 GUI；槽位内容和点击
处理分别由 container 包和事件负责。`title` 支持普通文本或 JSON Text
Component。

`mcs_player_set_screen_slot` 发送 clientbound Container Set Slot，更新已经打开
的 GUI 中一个槽位，不修改玩家的已跟踪背包。`container_id` 应与
`mcs_player_open_screen` 使用相同值；简单的纯可视菜单可以从 `state_id = 0`
开始。可选 `nbt_data` 使用与背包和 give API 相同的 ItemStack
`minecraft:custom_name` 规则。

示例：

```lua
mcs_player_open_book("Steve", "欢迎来到 OakMC！")
mcs_player_open_book("Steve", {
    "第一页：欢迎来到 OakMC！",
    "第二页：这些文字来自 Lua。",
})
mcs_player_open_written_book("Steve", {"只读第一页", "只读第二页"})
mcs_player_open_book_with_title("Steve", "服务器指南", {"欢迎", "规则"})
mcs_player_open_book_with_author("Steve", "Latos", "作者是 Latos")
mcs_player_open_book_components(
    "Steve",
    "OakMC 指南",
    "OakMC",
    {
        '{"text":"欢迎","color":"gold","bold":true}',
        '{"text":"执行 help","click_event":{"action":"run_command","command":"/help"}}',
    }
)

local WINDOW_ID = 1
local MENU_TYPE_GENERIC_9X1 = 0

mcs_player_open_screen("Steve", WINDOW_ID, MENU_TYPE_GENERIC_9X1, "OakMC Menu")
mcs_player_set_screen_slot("Steve", WINDOW_ID, 0, 0, 1, 1, nil)
```

BossBar UUID 使用普通文本 UUID，例如
`"00000000-0000-4000-8000-000000000001"`；`health` 范围是 `0.0..1.0`。
BossBar 标题、title/subtitle/Action Bar、GUI 标题、实体自定义名称和 spawn
名称都支持普通文本或 JSON Text Component。物品名称使用上面描述的
`nbt_data` 路径，当前只映射到 `minecraft:custom_name`。

```lua
mcs_title_set_text("Steve", '{"text":"Title","color":"gold","bold":true}')
mcs_player_open_screen("Steve", 1, 0, '{"text":"Menu","color":"blue"}')
mcs_player_set_screen_slot(
    "Steve", 1, 0, 0, 1, 1,
    '{"text":"Named item","color":"aqua","italic":false}'
)
```

常用常量：

- `MCS_BOSS_BAR_COLOR_PINK`、`MCS_BOSS_BAR_COLOR_BLUE`、
  `MCS_BOSS_BAR_COLOR_RED`、`MCS_BOSS_BAR_COLOR_GREEN`、
  `MCS_BOSS_BAR_COLOR_YELLOW`、`MCS_BOSS_BAR_COLOR_PURPLE`、
  `MCS_BOSS_BAR_COLOR_WHITE`
- `MCS_BOSS_BAR_DIVISION_NONE`、`MCS_BOSS_BAR_DIVISION_6`、
  `MCS_BOSS_BAR_DIVISION_10`、`MCS_BOSS_BAR_DIVISION_12`、
  `MCS_BOSS_BAR_DIVISION_20`
- `MCS_BOSS_BAR_FLAG_DARKEN_SKY`、`MCS_BOSS_BAR_FLAG_DRAGON_MUSIC`、
  `MCS_BOSS_BAR_FLAG_CREATE_FOG`

### 2.10 声音与 Title

#### mcs_player_play_sound

服务端

描述

向指定玩家播放数值 sound id 对应的声音。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收声音的在线玩家名。 |
| `sound_id` | `integer` | Minecraft `26.1.2` sound id。 |
| `category` | `integer` | 声音分类 ID。 |
| `volume` | `number` | 音量。 |
| `pitch` | `number` | 音高。 |
| `seed` | `integer` | 声音随机种子。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_play_sound("Steve", 1, 0, 1.0, 1.0, 0)
```

#### mcs_player_play_sound_name

服务端

描述

向指定玩家播放 registry sound name 对应的声音，例如 `minecraft:entity.player.levelup`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收声音的在线玩家名。 |
| `sound_name` | `string` | registry sound name。 |
| `category` | `integer` | 声音分类 ID。 |
| `volume` | `number` | 音量。 |
| `pitch` | `number` | 音高。 |
| `seed` | `integer` | 声音随机种子。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_player_play_sound_name("Steve", "minecraft:entity.player.levelup", 0, 1.0, 1.0, 0)
```

#### mcs_title_clear

服务端

描述

清除指定玩家客户端上的 Title 显示。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `reset_times` | `boolean` | 是否同时重置 Title 动画时间。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_title_clear("Steve", true)
```

#### mcs_title_set_action_bar_text

服务端

描述

设置玩家 Action Bar 文本。Action Bar 是经验栏上方短暂显示的小文本；传入空字符串可立即清除。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `text` | `string` | 普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_title_set_action_bar_text("Steve", "Hello")
```

#### mcs_title_set_subtitle_text

服务端

描述

设置玩家 Subtitle 文本。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `text` | `string` | 普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_title_set_subtitle_text("Steve", "By OakMC")
```

#### mcs_title_set_time

服务端

描述

设置玩家 Title 动画时间。时间单位是 tick。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `fade_in` | `integer` | 淡入 tick。 |
| `stay` | `integer` | 停留 tick。 |
| `fade_out` | `integer` | 淡出 tick。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_title_set_time("Steve", 10, 70, 20)
```

#### mcs_title_set_text

服务端

描述

设置玩家 Title 主标题文本。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `text` | `string` | 普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_title_set_text("Steve", '{"text":"OakMC","color":"gold"}')
```

`mcs_player_play_sound` 使用数值 sound id；`mcs_player_play_sound_name` 使用
`minecraft:entity.player.levelup` 这类 registry sound name。

Title 时间单位是 tick。

Action Bar 是经验栏上方短暂显示的小文本；传入空字符串可立即清除。

仍然导出以下旧 title 别名：

- `clear_title`
- `set_subtitle_text`
- `set_time`
- `set_title_text`

### 2.11 右侧排名榜与粒子

#### mcs_scoreboard_sidebar_show

服务端

描述

向指定玩家显示右侧侧边栏计分板。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `objective_name` | `string` | 客户端内部键，长度为 1-16 字节。 |
| `title` | `string` | 榜单标题，支持普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 显示成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_scoreboard_sidebar_show("Steve", "oakmc", "OakMC")
```

#### mcs_scoreboard_sidebar_update_title

服务端

描述

更新指定玩家右侧侧边栏计分板标题。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `objective_name` | `string` | 客户端内部键。 |
| `title` | `string` | 新标题，支持普通文本或 JSON Text Component。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 更新成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_scoreboard_sidebar_update_title("Steve", "oakmc", "New Title")
```

#### mcs_scoreboard_sidebar_set_score

服务端

描述

设置或更新右侧侧边栏计分板一行分数。`value` 用于决定行排序；`hide_value=true` 时隐藏客户端右侧数字，省略时默认为 `true`。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `objective_name` | `string` | 客户端内部键。 |
| `entry_name` | `string` | 计分板 entry 键。 |
| `value` | `integer` | 分数值，用于排序。 |
| `display_name` | `string` | 可选。行显示名，支持普通文本或 JSON Text Component。 |
| `hide_value` | `boolean` | 可选。是否隐藏右侧数字。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 设置成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_scoreboard_sidebar_set_score("Steve", "oakmc", "kills", 10, "Kills", true)
```

#### mcs_scoreboard_sidebar_remove_score

服务端

描述

移除右侧侧边栏计分板中的一行分数。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `objective_name` | `string` | 客户端内部键。 |
| `entry_name` | `string` | 要移除的 entry 键。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 移除成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_scoreboard_sidebar_remove_score("Steve", "oakmc", "kills")
```

#### mcs_scoreboard_sidebar_hide

服务端

描述

隐藏指定玩家的右侧侧边栏计分板。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 目标在线玩家名。 |
| `objective_name` | `string` | 客户端内部键。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 隐藏成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_scoreboard_sidebar_hide("Steve", "oakmc")
```

#### mcs_particle_spawn

服务端

描述

向指定玩家生成粒子。粒子名可以使用短名或完整名；Lua 暴露不需要额外数据的安全粒子路径，需要 ParticleOptions 额外数据的粒子会被拒绝。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `playername` | `string` | 接收粒子的在线玩家名。 |
| `particle_name_or_id` | `string` 或 `integer` | 粒子短名、完整名或协议粒子 ID。 |
| `x` / `y` / `z` | `number` | 粒子中心坐标。 |
| `offset_x` / `offset_y` / `offset_z` | `number` | 粒子偏移。 |
| `speed` | `number` | 粒子速度参数。 |
| `count` | `integer` | 粒子数量。 |
| `force_spawn` | `boolean` | 是否强制生成。 |
| `important` | `boolean` | 是否标记为重要粒子。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 发送成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_particle_spawn("Steve", "minecraft:flame", 0.5, 65.0, 0.5, 0.2, 0.2, 0.2, 0.0, 10, false, false)
```

`objective_name` 是长度为 1-16 字节的客户端内部键。榜单标题和可选的
`display_name` 支持普通文本或 JSON Text Component。`value` 仍用于决定行的
排序；`hide_value=true` 时使用 blank number format 隐藏客户端右侧显示的
数字，传 `false` 可恢复显示。省略时默认为 `true`。
粒子名可以使用短名
（`flame`）或完整名（`minecraft:flame`）。Lua 暴露不需要额外数据的安全粒子
路径；`block`、`dust`、`item`、`vibration`、`trail` 等需要 ParticleOptions
额外数据的粒子会被拒绝；协议 775 中的 `flash` 同样需要额外的 ARGB 颜色数据，
不能通过这个简化接口发送。

### 2.12 事件

#### mcs_event_register

服务端

描述

注册事件 handler。`priority` 按从大到小执行，数值越大越先执行。callback 会收到一个 table 参数。在 Lua 中设置 `event.cancelled = true` 会写回 C event，并在事件可取消时停止后续 handler。

参数

| 参数名 | 数据类型 | 说明 |
| --- | --- | --- |
| `event_type` | `integer` | 事件类型常量，例如 `MCS_EVENT_PLAYER_JOIN`。 |
| `priority` | `integer` | 优先级，数值越大越先执行。 |
| `callback` | `function` | 事件回调，签名为 `function(event)`。 |
| `options` | `table` | 可选。支持 `cancellable` 和 `cancelled`。 |

返回值

| 数据类型 | 说明 |
| --- | --- |
| `boolean` | 注册成功返回 `true`，失败返回 `false`。 |

示例

```lua
mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, function(event)
    mcs_server_send_message("player joined: " .. tostring(event.username), MCS_LOG_INFO)
end)
```

`priority` 按从大到小执行，数值越大越先执行。

`options` 可省略：

- `options.cancellable` 默认是 `true`
- `options.cancelled` 默认是 `false`

callback 会收到一个 table 参数。在 Lua 中设置 `event.cancelled = true` 会写回
C event，并在事件可取消时停止后续 handler。取消
`MCS_EVENT_BLOCK_BREAK` 时，Lua 层还会发送匹配的客户端 ack，因此脚本可以
阻止默认破坏路径，而不会让客户端挖掘 sequence 卡住。

通用事件字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `type` | `integer` | 事件类型常量，例如 `MCS_EVENT_PLAYER_JOIN`。 |
| `cancellable` | `boolean` | 该事件是否允许取消。 |
| `cancelled` | `boolean` | 事件是否已取消。Lua handler 可设置为 `true` 来取消可取消事件。 |
| `playername` | `string` | 可选。事件关联玩家的登录用户名。 |
| `username` | `string` | 可选。`playername` 的别名。 |
| `entity_id` | `integer` | 可选。事件关联玩家或实体的运行时实体 ID。 |

常见事件专用字段：

| 字段名 | 数据类型 | 说明 |
| --- | --- | --- |
| `message` | `string` | 聊天或系统消息文本。 |
| `x` / `y` / `z` | `number` | 事件关联坐标。 |
| `world_name` | `string` | 当前活动世界名，常见于出生点设置事件。 |
| `dimension_name` | `string` | 维度名称，常见于出生点设置事件。 |
| `block_x` / `block_y` / `block_z` | `integer` | 向下取整后的方块坐标。 |
| `yaw` / `pitch` | `number` | 事件关联朝向。 |
| `action` | `integer` | 协议动作 ID，例如方块破坏中的 Player Action。 |
| `hand` | `integer` | 手，`0` 主手，`1` 副手。 |
| `direction` | `integer` | 方块交互方向 ID。 |
| `sequence` | `integer` | 客户端交互 sequence，用于方块交互确认。 |
| `item_id` | `integer` | 事件关联物品 ID。 |
| `block_state_id` | `integer` | 事件关联 block state id。 |
| `inventory_id` | `integer` | 背包槽位 ID。 |
| `count` | `integer` | 物品数量。 |
| `source` | `integer` | 物品来源标识，常见于 `MCS_EVENT_PLAYER_RECEIVE_ITEM`。注意它不同于命令上下文里的 `context.source` 字符串。 |
| `cursor_x` / `cursor_y` / `cursor_z` | `number` | 方块交互时光标在方块内的位置。 |
| `inside_block` | `boolean` | 方块放置交互是否发生在方块内部。 |
| `world_border_hit` | `boolean` | 方块交互是否命中世界边界。 |
| `target_entity_id` | `integer` | 被攻击或被交互的目标实体 ID。 |
| `target_playername` | `string` | 如果目标实体是真实玩家，这里是目标玩家名。 |
| `target_username` | `string` | `target_playername` 的别名。 |
| `attacker_entity_id` | `integer` | 攻击者或交互发起者实体 ID。 |
| `container_id` | `integer` | GUI/container ID。 |
| `window_id` | `integer` | `container_id` 的别名。 |
| `inventory_type` | `integer` | 打开 Screen 时记录的 menu type id。 |
| `container_type` | `integer` | `inventory_type` 的别名。 |
| `state_id` | `integer` | container state id。 |
| `slot_id` | `integer` | 被点击或更新的槽位 ID。 |
| `button` | `integer` | 点击按钮；普通 pickup 中 `0` 为左键，`1` 为右键。 |
| `container_input` | `integer` | ContainerInput id：`0=PICKUP`、`1=QUICK_MOVE`、`2=SWAP`、`3=CLONE`、`4=THROW`、`5=QUICK_CRAFT`、`6=PICKUP_ALL`。 |
| `changed_slot_count` | `integer` | 客户端上报的 changed slot 数量。 |
| `first_changed_slot_id` | `integer` | 第一个 changed slot 的槽位 ID。 |
| `first_changed_item_id` | `integer` | 第一个 changed slot 的物品 ID。 |
| `first_changed_item_count` | `integer` | 第一个 changed slot 的物品数量。 |
| `carried_item_id` | `integer` | 鼠标光标携带物品 ID。 |
| `carried_item_count` | `integer` | 鼠标光标携带物品数量。 |
| `instance_name` | `string` | 新创建的子服实例名。 |
| `template_name` | `string` | 使用模板创建子服时的模板名。 |
| `port` | `integer` | 新创建子服的监听端口。 |

事件专用字段：

- `MCS_EVENT_PLAYER_CHAT`：`message`
- `MCS_EVENT_PLAYER_INITIALIZED`：新玩家客户端已经收到现有真实玩家、假玩家、
  普通实体、已记录装备和皮肤 metadata 后触发。需要只给新玩家补发 NPC 动画时
  应使用此事件，而不是较早触发的 `MCS_EVENT_PLAYER_JOIN`。
- `MCS_EVENT_HELD_ITEM_CHANGE`：玩家滚轮切换快捷栏后立即触发，携带
  `selected_inventory_id`、`item_id`、`block_state_id` 和 `count`。
- `MCS_EVENT_SERVER_INSTANCE_CREATED`：主服创建的子服开始接受连接后触发，携带
  `instance_name` 和 `port`；通过 `mcs_server_start_instance_from()` 创建时还会
  携带 `template_name`。
- `MCS_EVENT_WORLD_SPAWN_SET`：当前世界出生点成功写入存档后触发，携带
  `world_name`、`dimension_name`、精确坐标 `x`、`y`、`z`、向下取整后的
  `block_x`、`block_y`、`block_z`，以及 `yaw`、`pitch`。参数无效或持久化失败
  时不会触发。
- `MCS_EVENT_SYSTEM_CHAT`：`message`；在服务端发送 System Chat Message 前触发，
  可以通过 `event.cancelled = true` 取消发送；如果目标连接已关联玩家，还会包含
  通用的 `playername`、`username`、`entity_id` 字段
- `MCS_EVENT_BLOCK_BREAK`：`x`、`y`、`z`、`action`、`direction`、
  `sequence`、`block_state_id`
- `MCS_EVENT_BLOCK_PLACE`：`x`、`y`、`z`、`hand`、`direction`、
  `cursor_x`、`cursor_y`、`cursor_z`、`inside_block`、`world_border_hit`、
  `sequence`、`item_id`、`block_state_id`
- `MCS_EVENT_USE_ITEM`：可以来自 `Use Item On` 或 `Use Item`。前者携带与
  `MCS_EVENT_BLOCK_PLACE` 相同的方块交互字段；后者用于朝空气/直接使用手中物品，
  携带 `hand`、`sequence`、`yaw`、`pitch`、`item_id`、`block_state_id`
- `MCS_EVENT_USE_FOOD`：字段规则与 `MCS_EVENT_USE_ITEM` 相同，但在当前选中物品
  是食物时触发；`item_id` 是当前选中的快捷栏物品，`block_state_id` 是可用时
  映射出的放置状态
- `MCS_EVENT_RELEASE_USE_ITEM`：玩家停止使用当前物品时触发，对应
  `Player Action action == 5`；携带 `action`、`sequence`、`item_id`、
  `block_state_id`，可用于处理松开弓弦等动作
- `MCS_EVENT_SCREEN_CLICK`：`container_id`、`window_id`、`inventory_type`、
  `container_type`、`state_id`、`slot_id`、`button`、`container_input`、
  `changed_slot_count`、`first_changed_slot_id`、`first_changed_item_id`、
  `first_changed_item_count`、`carried_item_id`、`carried_item_count`
- `MCS_EVENT_PLAYER_RECEIVE_ITEM`：`inventory_id`、`item_id`、`count`、
  可选 `nbt_data` 和 `source`；handler 可以在默认背包更新前取消事件或改写字段
- `MCS_EVENT_ENTITY_ATTACK`：`target_entity_id`、`target_playername`、
  `target_username`、`attacker_entity_id`
- `MCS_EVENT_ENTITY_INTERACT`：`target_entity_id`、`target_playername`、
  `target_username`、`attacker_entity_id`
- `MCS_EVENT_SERVER_START`：当前只有 `type`

监听子服创建成功：

```lua
local function on_instance_created(event)
    mcs_server_send_message(
        string.format("实例 %s 已在端口 %d 启动", event.instance_name, event.port),
        MCS_LOG_INFO
    )
end

mcs_event_register(
    MCS_EVENT_SERVER_INSTANCE_CREATED,
    100,
    on_instance_created,
    { cancellable = false }
)
```

例如只给刚完成初始化的客户端恢复 NPC 拉弓姿势：

```lua
local function on_player_initialized(event)
    mcs_player_set_bow_animation(event.username, npc4_id, true, 0)
end

mcs_event_register(MCS_EVENT_PLAYER_INITIALIZED, 100, on_player_initialized)
```

`MCS_EVENT_PLAYER_JOIN` 仍适合服务端加入逻辑，但它触发时 NPC 可能还没有在新玩家
客户端生成，因此不应在 JOIN 中发送依赖该 NPC 已存在的 metadata。

方块破坏 `action` 使用协议 `Player Action` 值：

- `0`：开始破坏方块
- `1`：取消破坏方块
- `2`：停止/完成破坏方块

只希望每次挖掘触发一次的脚本通常应判断 `event.action == 0`。

Container click 说明：

- `container_input` 使用协议 `ContainerInput` id：
  `0=PICKUP`、`1=QUICK_MOVE`、`2=SWAP`、`3=CLONE`、`4=THROW`、
  `5=QUICK_CRAFT`、`6=PICKUP_ALL`
- 普通 pickup 点击中，`button == 0` 表示左键，`button == 1` 表示右键
- `inventory_type`/`container_type` 在 OakMC 发送
  `mcs_player_open_screen(...)` 时记录，不会由客户端点击包再次发送
- 被点击槽位的原始物品最终应来自服务端 GUI slot 状态；当前事件暴露客户端
  上报的 changed slot 和光标携带物品，足以支持简单菜单按钮和调试

示例：

```lua
local function on_break(event)
    if event.action ~= 0 then
        return
    end

    event.cancelled = true
    local state = mcs_block_get_state(event.x, event.y, event.z)
    mcs_block_broadcast_update(event.x, event.y, event.z, state)
end

mcs_event_register(MCS_EVENT_BLOCK_BREAK, 100, on_break)
```

## 3. 常量

事件常量：

- `MCS_EVENT_PLAYER_CHAT`
- `MCS_EVENT_SYSTEM_CHAT`
- `MCS_EVENT_PLAYER_JOIN`
- `MCS_EVENT_PLAYER_INITIALIZED`
- `MCS_EVENT_PLAYER_QUIT`
- `MCS_EVENT_PLAYER_MOVE`
- `MCS_EVENT_BLOCK_PLACE`
- `MCS_EVENT_BLOCK_BREAK`
- `MCS_EVENT_CREATIVE_SLOT_UPDATE`
- `MCS_EVENT_SERVER_START`
- `MCS_EVENT_SERVER_TICK`
- `MCS_EVENT_SERVER_INSTANCE_CREATED`
- `MCS_EVENT_WORLD_SPAWN_SET`
- `MCS_EVENT_ENTITY_ATTACK`
- `MCS_EVENT_ENTITY_INTERACT`
- `MCS_EVENT_USE_ITEM`
- `MCS_EVENT_USE_FOOD`
- `MCS_EVENT_SCREEN_CLICK`
- `MCS_EVENT_PLAYER_RECEIVE_ITEM`
- `MCS_EVENT_RELEASE_USE_ITEM`

日志常量：

- `MCS_LOG_DEBUG`
- `MCS_LOG_INFO`
- `MCS_LOG_WARN`
- `MCS_LOG_ERROR`

Gamemode 常量：

- `MCS_GAMEMODE_SURVIVAL`
- `MCS_GAMEMODE_CREATIVE`
- `MCS_GAMEMODE_ADVENTURE`
- `MCS_GAMEMODE_SPECTATOR`

Effect 常量：

- `MCS_EFFECT_INFINITE_DURATION = -1`
- `MCS_EFFECT_SPEED = 0`
- `MCS_EFFECT_SLOWNESS = 1`
- `MCS_EFFECT_HASTE = 2`
- `MCS_EFFECT_MINING_FATIGUE = 3`
- `MCS_EFFECT_STRENGTH = 4`
- `MCS_EFFECT_INSTANT_HEALTH = 5`
- `MCS_EFFECT_INSTANT_DAMAGE = 6`
- `MCS_EFFECT_JUMP_BOOST = 7`
- `MCS_EFFECT_NAUSEA = 8`
- `MCS_EFFECT_REGENERATION = 9`
- `MCS_EFFECT_RESISTANCE = 10`
- `MCS_EFFECT_FIRE_RESISTANCE = 11`
- `MCS_EFFECT_WATER_BREATHING = 12`
- `MCS_EFFECT_INVISIBILITY = 13`
- `MCS_EFFECT_BLINDNESS = 14`
- `MCS_EFFECT_NIGHT_VISION = 15`
- `MCS_EFFECT_HUNGER = 16`
- `MCS_EFFECT_WEAKNESS = 17`
- `MCS_EFFECT_POISON = 18`
- `MCS_EFFECT_WITHER = 19`
- `MCS_EFFECT_HEALTH_BOOST = 20`
- `MCS_EFFECT_ABSORPTION = 21`
- `MCS_EFFECT_SATURATION = 22`
- `MCS_EFFECT_GLOWING = 23`
- `MCS_EFFECT_LEVITATION = 24`
- `MCS_EFFECT_LUCK = 25`
- `MCS_EFFECT_UNLUCK = 26`
- `MCS_EFFECT_SLOW_FALLING = 27`
- `MCS_EFFECT_CONDUIT_POWER = 28`
- `MCS_EFFECT_DOLPHINS_GRACE = 29`
- `MCS_EFFECT_BAD_OMEN = 30`
- `MCS_EFFECT_HERO_OF_THE_VILLAGE = 31`
- `MCS_EFFECT_DARKNESS = 32`
- `MCS_EFFECT_TRIAL_OMEN = 33`
- `MCS_EFFECT_RAID_OMEN = 34`
- `MCS_EFFECT_WIND_CHARGED = 35`
- `MCS_EFFECT_WEAVING = 36`
- `MCS_EFFECT_OOZING = 37`
- `MCS_EFFECT_INFESTED = 38`
- `MCS_EFFECT_BREATH_OF_THE_NAUTILUS = 39`

## 4. 可直接使用的小示例

### 玩家加入欢迎

```lua
local function on_join(event)
    local player = event.playername
    if player == nil then
        return
    end

    mcs_title_set_time(player, 10, 70, 20)
    mcs_title_set_subtitle_text(player, "By Latos")
    mcs_title_set_text(player, "OakMC")
    mcs_player_play_sound_name(player, "minecraft:entity.player.levelup", 0, 1.0, 1.0, 0)
    mcs_player_set_effect(player, "speed", 254, 60, "icon")
end

mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, on_join)
```

### 聊天命令

```lua
local function on_chat(event)
    if event.message == "!where" then
        local info = mcs_player_get_info_by_name(event.playername)
        if info ~= nil then
            mcs_chat_send_system_message_all_player(
                string.format("%s is at %.1f %.1f %.1f", info.username, info.x, info.y, info.z)
            )
        end
    end
end

mcs_event_register(MCS_EVENT_PLAYER_CHAT, 10, on_chat)
```

### System Chat 事件

`MCS_EVENT_SYSTEM_CHAT` 会在服务端向某个目标连接发送 System Chat Message
之前触发。将要发送的文本位于 `event.message`；如果目标连接已经关联玩家，还可
使用通用的 `event.playername`、`event.username` 和 `event.entity_id` 字段。
广播消息会针对每个符合条件的目标分别触发事件，因此取消一次只会阻止该目标
收到消息。如果只想屏蔽某一条已知消息，建议使用完整文本比较。

```lua
mcs_event_register(MCS_EVENT_SYSTEM_CHAT, 0, function(event)
    print("system chat to " .. tostring(event.username) .. ": " .. event.message)
end)
```

如果不发送某条消息，可以设置 `event.cancelled = true`：

```lua
mcs_event_register(MCS_EVENT_SYSTEM_CHAT, 100, function(event)
    if event.message == "Server maintenance starts now" then
        event.cancelled = true
    end
end)
```

### Player Info 名称与世界名牌前缀

```lua
local function on_join(event)
    local player = event.playername
    if player == nil then
        return
    end

    -- Player Info/tab profile-name 路径：这里只传普通 profile name。
    mcs_player_set_custom_name(player, "ServerPlayer", true)

    -- 世界内名牌路径：prefix 会放在登录用户名之前。
    mcs_player_set_custom_prefix_name(
        player,
        '{"text":"[OakMC] ","color":"gold"}',
        true
    )
end

mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, on_join)
```

更完整的场景位于 `scripts/example/`。
