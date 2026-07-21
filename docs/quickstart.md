# OakMC 服务端上手指南

OakMC 是一款专为小游戏打造的高性能服务端。

这份指南会带你完成最常用的上手流程。OakMC 支持两种使用方式：推荐通过 OakManager 管理服务器，也可以直接运行 `mcserver` 手动管理单个服务端实例。

> 当前 OakMC 文档专为 0.0.1 版本编写。实际可用版本请以你拿到的发布包或构建产物说明为准。

## 1. 你会用到什么

一个可运行的 OakMC 服务端通常包含：

```text
mcserver/mcserver.exe    # OakMC 服务端程序
server.properties        # 主服务端配置，首次启动时会自动初始化
admin.properties         # Admin HTTP API 配置，首次启动时会自动初始化且默认关闭
remote.properties        # 跨服签名指令配置，可选
plugins/                 # Lua 插件目录
log/                     # 服务端日志目录
crashes/                 # 崩溃转储目录
world/                   # 默认世界目录，名称由 server.properties 的 level-name 决定
```

## 2. 第一次启动

OakMC 可以通过两种方式启动和管理。日常使用建议选择 OakManager，它会更适合管理服务器生命周期、配置、日志和多个服务端实例；如果你只想快速验证或需要自行接入现有进程管理工具，也可以直接运行 `mcserver`。

### 方式一：使用 OakManager（推荐）

建议使用 OakManager 创建和管理 OakMC 服务器。通过 OakManager 管理时，你通常不需要手动维护每个实例的工作目录，也不需要直接操作启动命令；服务器启动、停止、配置调整、日志查看和实例管理都应优先在 OakManager 中完成。
![OakManager_snapshot](/archive/oak_manager_snapshot.png "本地图片标题")
使用 OakManager 时，请在管理界面中创建 OakMC 服务器，并按界面提示选择服务端程序、工作目录、端口和最大玩家数等参数。创建完成后，从 OakManager 启动服务器，再按下文的连接测试方式进入游戏验证。

### 方式二：直接运行 mcserver

如果不使用 OakManager，建议为每一个服务端实例准备一个独立工作目录。OakMC 会在当前工作目录中创建配置、日志、插件目录和世界数据。

进入工作目录后启动：

```bash
./mcserver
```


查看可用启动参数：

```bash
./mcserver --help
```

常用启动参数：

```bash
./mcserver --port 25565 --max-players 20
```

也可以使用等号写法：

```bash
./mcserver --port=25566 --max-players=50
```

可用参数包括：

| 参数 | 作用 |
| --- | --- |
| `-p`, `--port`, `--server-port` | 设置 Minecraft 服务端口 |
| `-m`, `--max-players`, `--players` | 设置最大玩家数 |
| `--remote-address` | 设置跨服签名指令监听地址 |
| `--remote-port` | 设置跨服签名指令监听端口 |
| `--remote-id` | 设置当前服务端的远程标识 |
| `--remote-secret-file` | 从文件读取远程签名密钥 |
| `--remote-allowed-commands` | 设置允许远程执行的命令白名单 |
| `-h`, `--help` | 查看帮助 |

端口范围是 `1 ~ 65535`，最大玩家数至少为 `1`。如果参数非法，程序会提示并退出。

## 3. 基础配置

OakMC 的主要配置文件是 `server.properties`。首次启动后如果文件不存在，服务端会自动创建。

常用配置项：

| 配置项 | 说明 |
| --- | --- |
| `server-address` | Minecraft 服务监听的 IPv4 地址 |
| `server-port` | Minecraft 服务端口，默认通常为 `25565` |
| `max-players` | 最大玩家数，同时影响状态响应 |
| `online-mode` | 是否启用 Mojang session 校验 |
| `white-list` | 是否要求玩家存在于 `whitelist.json` |
| `allow-flight` | 是否允许飞行 |
| `difficulty` | 默认难度 |
| `gamemode` | 默认游戏模式，支持 `survival`、`creative`、`adventure`、`spectator` 或 `0..3` |
| `motd` | 服务器列表描述 |
| `level-name` | 当前活动世界目录，默认是 `world` |
| `level-seed` | 新建 `level.dat` 时使用的种子 |
| `view-distance` | 玩家区块发送半径 |
| `world-chunk-cache-size` | 共享区块缓存容量，此值越高运行时内存的占用越多 |
| `session_server_url` | online mode 使用的 session 校验地址 |

配置覆盖顺序通常是：

```text
配置文件 -> 环境变量 / 命令行覆盖 -> 当前进程运行状态
```

命令行覆盖只影响当前进程，不会自动写回 `server.properties`。

需要注意：

- 修改端口或监听地址后，需要重启服务端。
- 执行 `reload` 可以重载部分配置和 Lua 插件，但不会重新绑定端口。
- 修改 `level-seed` 不会重写已有世界的种子，已有世界以 `level.dat` 为准。
- 服务端默认使用 Mojang 登录认证服务，如果您使用第三方认证登录认证服务，请修改 `session_server_url`。

## 4. 连接测试

服务端启动成功后，打开 Minecraft 客户端，进入多人游戏并添加服务器。

本机测试：

```text
127.0.0.1:25565
```

如果你改过端口，请把 `25565` 换成实际端口。

局域网测试可以使用运行服务端机器的局域网 IP，例如：

```text
192.168.1.10:25565
```

公网访问需要确保云服务器安全组、防火墙或路由器端口转发已经放行对应端口。

## 5. 常用控制台命令

这些命令可以在服务端控制台执行。部分命令也可以由有权限的玩家在游戏内执行。更完整的
参数说明和示例见 [命令示例](/docs/command-examples)。

### 基础管理

| 命令 | 作用 |
| --- | --- |
| `help` | 查看当前可用命令和用法 |
| `list` | 查看在线玩家和在线人数 |
| `say <内容>` | 向所有在线玩家广播消息 |
| `op <玩家名>` | 授予在线玩家 OP，并刷新其命令列表 |
| `deop <玩家名>` | 移除玩家 OP |
| `reload` | 重载配置和 Lua 插件；`level-name` 变化时会顺带切换活动世界 |
| `reload-lua` | 仅重载 Lua 插件 |
| `stop` | 优雅关闭服务端 |

### 玩家与世界

| 命令 | 作用 |
| --- | --- |
| `where <玩家名>` | 查看玩家当前位置和相关信息 |
| `tp <玩家名> <x> <y> <z>` | 传送玩家到指定坐标 |
| `gamemode <玩家名> <模式>` | 修改玩家游戏模式 |
| `sethealth <玩家名> <血量> <最大血量> <吸收值>` | 调整玩家血量，常用于测试和调试 |
| `kick <玩家名>` | 踢出玩家 |
| `transfer <玩家名> <主机> <端口>` | 让客户端转服到另一台服务端 |
| `world current` | 查看当前活动世界 |
| `world load <名称>` | 切换活动世界并保留在线连接 |

### 物品、实体与环境

| 命令 | 作用 |
| --- | --- |
| `give <玩家名> <物品> [数量] [名称]` | 给玩家发放物品 |
| `setitem <玩家名> <槽位> <物品> [数量] [名称]` | 设置指定背包槽位的物品 |
| `spawn <实体> <x> <y> <z> ...` | 按注册名或数字 ID 生成实体 |
| `block <x> <y> <z> <方块>` | 设置指定坐标的方块或 block state |
| `weather <clear|rain|thunder> <tick>` | 修改天气和持续时间 |
| `playsoundname <玩家名> <声音名> <类别> [...]` | 用声音注册名播放声音 |
| `playsound <玩家名> <声音ID> <类别> [...]` | 用声音数字 ID 播放声音 |
| `effect <玩家名> <效果> <等级> <时长> [flags]` | 给玩家添加状态效果 |
| `title <玩家名> ...` | 设置标题、字幕、时间或清除标题 |
| `sidebar <玩家名> ...` | 显示、更新或隐藏右侧计分板 |
| `particle <玩家名> <粒子> <x> <y> <z> ...` | 向指定玩家发送粒子效果 |

关闭服务端时请使用：

```text
stop
```

这比直接关闭窗口或强制结束进程更安全。

更多命令示例见 [命令示例](/docs/command-examples)。

## 6. 世界切换

查看当前世界：

```text
world current
```

切换到另一个世界：

```text
world load arena
```

世界名只允许字母、数字、`_` 和 `-`。如果目标世界目录不存在，服务端会自动创建。

切换世界时，OakMC 会保存并停止旧世界区块任务，重载 Lua 插件，清理普通运行时实体，向在线玩家发送 Respawn，并把玩家传送到新世界出生点。

## 7. Lua 插件

OakMC 内嵌 Lua 5.4，用于玩法插件和服务端实验。

插件放在：

```text
plugins/*.lua
```

每个插件通常返回一个模块表：

```lua
local function init()
    mcs_server_send_message("hello from plugin", MCS_LOG_INFO)
end

local function shutdown()
    mcs_server_send_message("plugin stopped", MCS_LOG_INFO)
end

return {
    name = "example",
    depends = {},
    init = init,
    shutdown = shutdown,
}
```

重载 Lua 插件：

```text
reload-lua
```

插件开发快速上手见 [插件开发](/docs/plugin-development-zh)。完整 Lua API
见 [Lua API 参考](/docs/lua-api-reference-zh)。英文版见 [English Lua API reference](/docs/lua-api-reference)。

## 8. 跨服签名指令

OakMC 支持可选的跨服签名指令桥。缺少 `remote.properties` 或设置 `enabled=false` 时，该功能默认关闭。

一个基础配置示例：

```properties
enabled=true
listen-address=127.0.0.1
listen-port=25575
server-id=hub
secret=replace-with-a-generated-secret
allowed-commands=say,list,weather
```

建议使用至少 32 个字符的密钥，并只在可信服务端集群中共享。

生产环境更推荐使用密钥文件：

```bash
./mcserver \
  --remote-port 25575 \
  --remote-id hub \
  --remote-secret-file /run/secrets/oakmc-remote \
  --remote-allowed-commands say,list,weather
```

不要把明文密钥写进命令行历史或公开日志。

详细说明见 [服务器运维](/docs/server-operations-zh)。

## 9. Admin HTTP API

OakMC 会自动创建 `admin.properties`，但 Admin HTTP API 默认关闭。

如果你需要使用管理面板、自动化运维脚本或远程管理功能，请先阅读运维文档并按需开启。

建议：

- 不要在公网裸露管理接口。
- 为管理接口设置强凭据。
- 优先绑定到 `127.0.0.1` 或内网地址。
- 配合反向代理、访问控制或 VPN 使用。

详细配置见 [服务器运维](/docs/server-operations-zh)。

## 10. 日常维护建议

建议在以下操作前备份服务端目录：

- 更新 OakMC 程序
- 修改 `server.properties`
- 添加或删除 Lua 插件
- 切换或导入世界
- 开启远程指令或 Admin API
- 对外开放给更多玩家

建议重点备份：

```text
server.properties
admin.properties
remote.properties
plugins/
log/
world/
whitelist.json
banned-players.json
banned-ips.json
```

如果你的 `level-name` 不是 `world`，请备份实际世界目录。

## 11. 常见问题

### 启动后端口占用

可以换一个端口启动：

```bash
./mcserver --port 25566
```

也可以检查是否已有另一个服务端实例正在运行。

### 修改端口后 reload 没生效

这是正常行为。`reload` 不会重新绑定监听 socket。修改 `server-address` 或 `server-port` 后需要重启服务端。

### 玩家无法连接

请检查：

- 服务端是否已经启动成功
- 客户端版本是否匹配当前协议实现
- IP 和端口是否填写正确
- 防火墙、安全组或端口转发是否放行
- `online-mode`、`white-list` 是否符合预期

### Lua 插件没有加载

请检查：

- 文件是否放在 `plugins/*.lua`
- 插件是否返回了正确的模块表
- `init()` 是否存在
- `depends` 是否写错或出现循环依赖
- 控制台和 `log/` 中是否有 Lua 报错

### 世界切换失败

请检查世界名是否只包含字母、数字、`_` 和 `-`。不要使用空格、中文或特殊符号作为 `world load` 的目标名称。

## 12. 文档入口

| 文档 | 内容 |
| --- | --- |
| [服务器运维](/docs/server-operations-zh) | 中文运维说明、启动参数、配置、reload、远程指令、Admin API |
| [Operations guide](/docs/server-operations) | English operations guide |
| [命令示例](/docs/command-examples) | 控制台命令、物品、实体、方块、天气、声音等示例 |
| [插件开发](/docs/plugin-development-zh) | 中文 Lua 插件开发快速上手 |
| [Lua API 参考](/docs/lua-api-reference-zh) | 中文 Lua API 参考 |
| [English Lua API reference](/docs/lua-api-reference) | English Lua API reference |

## 13. 反馈问题时请提供

为了更快定位问题，反馈时请尽量提供：

- OakMC 版本或构建来源
- 操作系统
- 启动命令
- `server.properties` 中相关配置
- 控制台输出或 `log/` 中的报错
- 若服务端崩溃，提供 `crashes` 文件夹最新的错误转储文件
- 是否使用 Lua 插件
- 最近是否修改过配置、插件、世界或远程管理功能

---

<p align="center">
  <strong>OakMC 服务端</strong><br />
  从启动、连接、管理到扩展，一份面向用户的快速上手入口。
</p>
