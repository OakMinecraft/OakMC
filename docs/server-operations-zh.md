# OakMC 服务端运行与运维

[English](server-operations.md)

本文说明当前 OakMC 运行时的工作目录模型、启动参数、配置重载、跨服签名指令、
Admin HTTP API 和隔离子实例。

## 1. 工作目录


OakMC 第一次启动时会初始化 `server.properties`、`plugins/` 、`crashes`。需要相互独立的服务端安装时，应当从不同的专用工作目录运行同一二进制。

常见运行时路径：

- `server.properties`：主服务端配置
- `admin.properties`：可选的 OakMC Manager / Admin HTTP API 配置
- `server-icon.png`：由管理员提供的可选状态图标
- `remote.properties`：可选的跨服签名指令配置
- `plugins/*.lua`：按依赖顺序加载的 Lua 插件
- `log/`：带时间戳的服务端日志
- `<level-name>/level.dat`：原版 Java 世界元数据和种子
- `<level-name>/region/*.mca`：原版 Java Anvil region 文件
- `whitelist.json`、`banned-players.json`、`banned-ips.json`：管理数据
- `instances/<name>/`：子服务端实例工作目录
- `crashes/`：Breakpad 启用且初始化成功时的转储目录

`admin.properties` 会自动创建，且默认关闭 Admin API。`remote.properties` 和
`server-icon.png` 都不会自动生成。

## 2. 启动参数

查看二进制接受的参数：

```bash
./build-debug/src/mcserver --help
```

当前参数：

```text
-p, --port, --server-port PORT
-m, --max-players, --players PLAYERS
--remote-address ADDRESS
--remote-port PORT
--remote-id ID
--remote-secret-file PATH
--remote-allowed-commands COMMANDS
-h, --help
```

长参数既可以把值写在下一项，也可以使用 `--option=value`：

```bash
./build-debug/src/mcserver --port 25566 --max-players=50
```

Remote 参数既可以覆盖 `remote.properties`，也可以在该文件不存在时直接配置签名桥：

```bash
./build-debug/src/mcserver \
  --remote-port 25576 \
  --remote-id survival \
  --remote-secret-file /run/secrets/oakmc-remote \
  --remote-allowed-commands stop,say
```

端口范围为 `1..65535`，最大玩家数必须至少为 `1`。未知参数或非法值会打印
usage，并在运行时初始化之前以状态码 `2` 退出。

程序会先读取配置文件，再应用环境变量和命令行覆盖。覆盖只影响当前进程，不会
改写任何 properties 文件；执行 `reload` 后会重新应用服务端覆盖，执行
`remote reload` 后会重新应用 Remote 覆盖。reload 不会重新绑定监听 socket，
因此修改端口或地址后必须重启。

每个已接受的 Minecraft 连接都必须在大约 5 秒内发送完整的初始 Handshake；
status 和 login 收包也使用有限等待。非法 packet frame、截断字段、非预期 packet
id，以及不符合当前状态 schema 的 payload 都会被拒绝并关闭连接。这些限制目前
属于编译期确定的运行时行为，不是 `server.properties` 配置项。

## 3. `server.properties`

当前维护的配置键：

| 键 | 用途 |
| --- | --- |
| `server-address` | Minecraft 服务监听的 IPv4 地址 |
| `server-port` | Minecraft 服务端口；运行时默认端口为 `25565` |
| `max-players` | 状态响应和登录容量 |
| `online-mode` | 启用 Mojang session 校验 |
| `white-list` | 要求玩家存在于 `whitelist.json` |
| `allow-flight` | 服务端飞行策略 |
| `difficulty` | 默认难度名 |
| `gamemode` | `survival`、`creative`、`adventure`、`spectator` 或 `0..3` |
| `motd` | 服务器列表描述 |
| `level-name` | 唯一活动存档目录，默认 `world` |
| `level-seed` | 新建 `level.dat` 时使用的种子 |
| `view-distance` | 区块发送半径 |
| `world-chunk-cache-size` | 共享区块缓存容量；小于 `1024` 的值会被忽略 |
| `session_server_url` | online mode 使用的 session 校验地址 |

已有世界以 `level.dat` 中记录的种子为准；修改 `level-seed` 不会重写现有世界
种子。当前 OakMC 只使用主世界 region 目录。存档中不存在的区块会初始化为空
区块，因为主线运行时当前不包含地形生成。

除非明确部署了兼容认证服务，否则请保留默认 `session_server_url`。

## 4. Reload 与世界切换

相关控制台命令：

```text
reload
reload-lua
world current
world load <name>
remote reload
```

- `reload` 在不踢出在线玩家的情况下重载 `server.properties` 和 Lua 插件，并
  重新应用命令行端口/人数覆盖。`level-name` 改变时会执行与 `world load` 相同
  的保连接世界切换。
- `reload-lua` 按依赖顺序的反向卸载插件，再重新加载，但不会重新读取
  `server.properties`。
- `world load <name>` 会保存并静止旧区块缓存，重载 Lua 以清理世界所属状态，
  发送 Respawn，把玩家传送到新出生点并重建区块队列。名称只允许字母、数字、
  `_` 和 `-`。
- `remote reload` 重新读取本机身份、共享密钥和指令白名单，然后重新应用
  `OAKMC_REMOTE_SECRET` 与 Remote 启动参数。修改 `listen-address` 或
  `listen-port` 后需要重启，监听器才会重新绑定。

## 5. 跨服签名指令桥

缺少 `remote.properties` 或设置 `enabled=false` 时，该功能保持关闭。配置方式：

```bash
cp remote.properties.example remote.properties
openssl rand -hex 32
```

把生成结果写入 `secret`，为每台服务端选择唯一的 `server-id`；只有同一可信
集群中的服务端才应共享同一个 secret。

```properties
enabled=true
listen-address=127.0.0.1
listen-port=25575
server-id=hub
secret=replace-with-a-generated-secret
allowed-commands=say,list,weather
```

配置行为：

- `listen-address` 和 `listen-port` 描述当前服务端的入站监听器。
- `server-id` 标识当前接收端，并会与每个请求中的目标 id 比较。
- `secret` 至少 32 个字符，且不会暴露给 Lua。
- `allowed-commands` 是根据第一段命令名匹配的逗号分隔白名单；空值会拒绝所有
  入站指令。
- 该文件不保存固定出站 peer。目标 id、IPv4 地址和端口由 `remote send` 或
  `mcs_remote_command_send()` 调用时提供。

启动覆盖的优先级从高到低为：

```text
Remote 命令行参数
OAKMC_REMOTE_SECRET（仅覆盖 secret）
remote.properties
内置默认值
```

出现任意 Remote 命令行参数都表示本进程需要启用签名桥；合并后的最终配置必须
包含合法的 `server-id` 和至少 32 字符的 secret。缺少 `remote.properties` 时，
监听地址与端口默认为 `127.0.0.1:25575`；未提供或明确设置为空的指令白名单会
拒绝所有入站指令。

进程管理器和容器应使用 `--remote-secret-file PATH`。`remote reload` 会重新读取
该文件，文件内容首尾空白会被忽略，密钥内容不会写入日志。OakMC 特意不提供明文
`--remote-secret` 参数，因为命令行可能通过进程列表和 shell 历史泄露。
`OAKMC_REMOTE_SECRET` 可用于更适合环境变量的部署，但密钥文件通常更不容易被
意外暴露。

示例：

```text
remote send survival 127.0.0.1 25576 say Maintenance in 5 minutes
```

请求使用 HMAC-SHA256，签名材料包含来源 id、目标 id、时间戳、随机 nonce 和完整
指令。接收端先检查 30 秒时钟窗口和 nonce 重放缓存，再以控制台/OP 上下文执行；
接收端的命令白名单仍然生效。

应尽量只监听 loopback。跨主机部署时，请使用防火墙或私有 VPN、保持系统时钟
同步、收紧白名单，并且不要在插件源码或日志中暴露集群 secret。

## 6. Admin HTTP API

OakMC 内置了一个可选的 HTTP 控制 API，主要供 OakMC Manager 和运维工具使用。
它不写入 `server.properties`，而是通过独立的 `admin.properties` 配置。首次启动
会自动生成该文件，并保持关闭：

```properties
# OakMC Manager / Admin HTTP API
# Keep disabled unless you need GUI or remote management.
enabled=false
listen-address=127.0.0.1
listen-port=25580
# Required when enabled. Use at least 32 random characters.
token=
allow-origin=http://127.0.0.1:1420
```

启用时，设置 `enabled=true`，生成至少 32 个随机字符的 token，然后重启服务端：

```bash
openssl rand -hex 32
```

配置行为：

- `listen-address` 和 `listen-port` 决定 HTTP 监听地址；当前只接受 IPv4 地址。
- `token` 在启用后必填，并会校验每个接口请求。
- `allow-origin` 控制浏览器工具看到的 CORS `Access-Control-Allow-Origin`。
  使用 GUI 时应尽量设置为明确来源。
- Admin API 配置只在进程启动时读取。修改地址、端口、token 或 CORS 来源都需要
  重启。

普通 HTTP 客户端应使用 Bearer token 鉴权：

```bash
curl -H "Authorization: Bearer $OAKMC_ADMIN_TOKEN" \
  http://127.0.0.1:25580/api/v1/status
```

实现也接受 `?token=...` 查询参数，方便浏览器 `EventSource` 这类无法设置
`Authorization` 头的客户端使用。普通请求应优先使用 header，避免 token 出现在
日志或被复制的 URL 中。

当前接口：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/api/v1/status` | 返回服务端版本、协议、监听地址、玩家数量和视距 |
| `GET` | `/api/v1/players` | 列出在线玩家的名称、UUID、entity id、协议和初始化状态 |
| `POST` | `/api/v1/command` | 以 JSON body `{"command":"say hello"}` 执行控制台/OP 指令 |
| `POST` | `/api/v1/players/<name>/kick` | 踢出在线玩家 |
| `POST` | `/api/v1/players/<name>/ban` | 封禁玩家；body 可包含 `{"kick":true}` |
| `GET` | `/api/v1/plugins` | 列出 `plugins/*.lua` 和 `plugins/*.lua.disabled` |
| `PATCH` | `/api/v1/plugins/<file>` | 通过 `{"enabled":true}` 启用或禁用插件 |
| `POST` | `/api/v1/plugins/<file>/enable` | 把 `<file>.disabled` 重命名回 `<file>` |
| `POST` | `/api/v1/plugins/<file>/disable` | 把 `<file>` 重命名为 `<file>.disabled` |
| `POST` | `/api/v1/plugins/reload` | 执行 `reload-lua` |
| `GET` | `/api/v1/events` | Server-Sent Events 事件流，包含日志行和推断出的玩家进出事件 |

成功的 JSON 响应为 `{"ok":true,...}` 或 `{"ok":true}`。错误响应为
`{"ok":false,"error":"..."}`，并带对应 HTTP 状态码。SSE 会发送
`log_line`、`player_join` 和 `player_left` 事件；玩家进出事件目前从日志行推断，
适合作为界面提示，不应替代权威的在线玩家状态查询。

该 API 可以执行控制台命令、修改插件文件并暴露实时服务端状态。应尽量只监听
loopback。确实需要跨主机访问时，请放在 TLS 终止和网络访问控制之后；OakMC 内置
Admin 监听器是明文 HTTP，安全性依赖 Bearer token 和外围网络边界。

## 7. 隔离子实例

Lua 插件可以查找空闲端口并启动另一个 OakMC 进程：

```lua
local port = mcs_server_find_available_port(10000)
assert(port ~= nil)
assert(mcs_server_start_instance("arena_1", port))
```

分配固定端口范围时，可以使用 `mcs_server_port_is_available(port)` 对单个端口执行
本地 bind 探测。返回 `true` 表示当前可以绑定，返回 `false` 通常表示端口已被占用，
但 socket 或 bind 出错时也会返回 `false`。它不会连接 Minecraft 服务端查询状态。
它也不能识别监听进程或监控子进程健康状态。

提供 Remote 端口和可选入站白名单即可请求独立的子服 Remote 监听器：

```lua
local game_port = assert(mcs_server_find_available_port(10000))
local remote_port = assert(mcs_server_find_available_port(20000))
assert(mcs_server_start_instance(
    "arena_1", game_port, remote_port, "stop,say"))
```

白名单使用不带空格的逗号分隔命令名。

C 层使用实例名作为子服 `server-id`，并通过实例目录内权限受限的保留文件转发
父进程最终生效的 secret（类 Unix 系统权限为 `0600`）；Lua 不读取也不写入密钥。
如果父进程没有有效 Remote secret，子服仍会在 Minecraft 端口正常启动，但 C 不传
Remote 参数，子服 Remote 保持关闭。

需要从同一个小游戏模板创建多个隔离房间时，使用模板启动接口：

```lua
local port = assert(mcs_server_find_available_port(10000))
local remote_port = assert(mcs_server_find_available_port(20000))
assert(mcs_server_start_instance_from(
    "arena-template", "arena-room-1", port, remote_port, "stop"))
```

模板接口复制世界、插件和服务端配置，但跳过 `log/`、`crashes/`、
`remote.properties` 与保留的实例密钥文件。因此每个房间拥有独立世界数据，也不会
复用模板的 Remote 监听端口或凭据。模板函数接受相同的可选 `remote_port` 和
`allowed_commands` 参数。插件需要自行分配互不冲突的游戏端口和 Remote 端口，
并定义自己的发现、健康检查与恢复策略。

如果这些房间位于 Velocity 后方，应把唯一的 OakMC 子进程实例名与代理注册名
分开。代理注册名由调用插件决定；同一个逻辑后端重新注册时应保持稳定。固定单主机
拓扑可以只按端口命名，多主机部署则应加入稳定的主机标识，避免名称冲突。OakMC
本身不规定大厅名称或后端命名方式。

动态房间内的插件可以在无人时调用
`mcs_server_delete_current_instance()`。该调用会先优雅关闭当前子服，再删除带房间
标记的工作目录；它不能用于删除主服、模板或普通子实例。

子进程使用同一可执行文件和 `--port <port>`，工作目录为
`instances/arena_1/`。子服 Remote 生效时，C 还会传递 `--remote-port`、
`--remote-id`、`--remote-secret-file` 和可选白名单。子服会创建并独立拥有自己的
`server.properties`、世界、插件、管理文件和日志。父进程的经济数据、公告、玩家
状态和 `remote.properties` 都不会复制；需要明确的跨服指令或状态协调时应使用
签名桥。

实例名只允许字母、数字、`_` 和 `-`，请求端口不能等于父服务端的最终端口。
只有子进程开始接受 loopback 连接后，启动调用才会成功。端口探测和子进程启动
之间仍然存在竞争窗口，因此调用方必须处理失败。不要同时运行两个同名子实例：
即使请求了不同端口，同一个实例名仍然直接映射到同一个工作目录。

在类 Unix 系统上，子进程会脱离终端，标准输入输出重定向到 `/dev/null`；排错时
应查看 `instances/<name>/log/`。当前没有成对的实例停止 API。只有在子实例入站
白名单明确包含 `stop` 时，才可使用认证后的远程 `stop`，否则应由所属插件实现
其他明确的生命周期策略。

## 8. 跨进程文件锁

多个 OakMC 进程明确需要更新同一个本地文件时，Lua 可以使用运行时提供的 advisory
排他锁：

```lua
local lock_id = mcs_server_file_lock("/srv/oakmc/shared/economy.lock", 2000)
if lock_id == nil then
    return false
end

-- 在这里读取、更新并替换受保护的数据文件。

assert(mcs_server_file_unlock(lock_id))
```

超时时间单位为毫秒，不能为负数。锁 ID 只在当前进程内有效，每个进程最多同时
持有 32 个锁。成功加锁后应始终主动释放；进程退出时操作系统也会释放它。

子实例的工作目录彼此不同。如果该锁用于协调多个实例，应使用绝对路径，或者确保
每个进程解析出的路径都指向同一个锁文件。文件锁只保护本地文件访问，不会复制
数据，也不能替代跨服签名指令桥。

## 9. 运维检查清单

对玩家开放服务端之前：

1. 确认客户端版本为 Minecraft `26.1.2` / protocol `775`。
2. 检查 `server-address`、`server-port`、`online-mode`、`white-list` 和
   `max-players`。
3. 测试世界存储改动前备份 `level.dat` 和 `region/*.mca`。
4. 保密 `remote.properties`，并尽量缩小监听范围。
5. 除非需要，否则保持 Admin HTTP API 关闭；启用时应收窄监听范围，并使用至少
   32 个字符的随机 token。
6. 运行 `ctest --test-dir build-debug --output-on-failure` 验证运行时改动。
7. 检查 `log/` 中的世界 DataVersion 拒绝、认证错误、插件依赖失败和跨服桥
   配置错误。
