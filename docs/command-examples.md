# OakMC 命令与运行时示例

下面的控制台命令基于当前 Minecraft `26.1.2` / protocol `775` 实现。
示例玩家名使用 `Latos_`，坐标按测试世界自行调整。
Lua 函数的完整中文说明见
[`lua-api-reference-zh.md`](lua-api-reference-zh.md)。

## 命令速查

下面这张表先回答“这个命令是干什么的”。后面的章节再给出更接近真实使用场景的组合
示例。命令名均可直接输入到 OakMC 控制台；其中一部分也会出现在玩家客户端的命令列表里。

### 基础管理

| 命令 | 说明 |
| --- | --- |
| `help` | 查看当前注册的命令帮助，通常会显示命令名和用法。 |
| `list` | 查看在线玩家列表和在线人数。 |
| `say <内容>` | 向所有在线玩家广播一条消息。 |
| `op <玩家名>` | 授予指定在线玩家 OP 权限，并刷新其可用命令。 |
| `deop <玩家名>` | 取消指定玩家的 OP 权限。 |
| `reload` | 重载配置和 Lua 插件；如果活动世界名发生变化，也会顺带切换世界。 |
| `reload-lua` | 只重载 Lua 插件，不重新读配置。 |
| `stop` | 优雅关闭服务端。 |

### 玩家与世界

| 命令 | 说明 |
| --- | --- |
| `world current` | 查看当前活动存档。 |
| `world load <名称>` | 切换到另一个活动存档，并保留在线连接。 |
| `where <玩家名>` | 查看目标玩家的当前位置。 |
| `tp <玩家名> <x> <y> <z>` | 把玩家传送到指定坐标。 |
| `tp <玩家名> <x> <y> <z> <yaw> <pitch>` | 传送并同时设置朝向。 |
| `gamemode <玩家名> <模式>` | 修改玩家游戏模式。 |
| `sethealth <玩家名> <血量> <最大血量> <吸收值>` | 调整玩家血量，常用于调试和测试。 |
| `kick <玩家名>` | 将玩家踢出服务器。 |
| `transfer <玩家名> <主机> <端口>` | 发送 transfer 包，让客户端切到另一台服务端。 |

### 物品与实体

| 命令 | 说明 |
| --- | --- |
| `give <玩家名> <物品> [数量] [名称]` | 给玩家发放物品，`名称` 可用普通文本或自定义名称输入。 |
| `setitem <玩家名> <槽位> <物品> [数量] [名称]` | 直接设置指定背包槽位的物品。 |
| `spawn <实体> <x> <y> <z> ...` | 生成实体，可用注册名或当前版本的数字 ID。 |
| `block <x> <y> <z> <方块>` | 设置指定坐标的方块，可用方块名或 block state id。 |

### 环境与显示

| 命令 | 说明 |
| --- | --- |
| `weather <clear|rain|thunder> <tick>` | 修改天气类型和持续时间。 |
| `playsoundname <玩家名> <声音名> <类别> [...]` | 按声音注册名播放声音。 |
| `playsound <玩家名> <声音ID> <类别> [...]` | 按声音数字 ID 播放声音。 |
| `effect <玩家名> <效果> <等级> <时长> [flags]` | 给玩家添加状态效果，时长可写 `infinite`。 |
| `title <玩家名> times <fade_in> <stay> <fade_out>` | 设置标题显示时间。 |
| `title <玩家名> title <内容>` | 设置主标题。 |
| `title <玩家名> subtitle <内容>` | 设置副标题。 |
| `title <玩家名> clear [true]` | 清空标题，`true` 时也会重置时序。 |
| `sidebar <玩家名> show <objective> <title>` | 显示右侧计分板。 |
| `sidebar <玩家名> update <objective> <title>` | 更新右侧计分板标题。 |
| `sidebar <玩家名> set <objective> <entry> <value> [display_name]` | 设置或更新一行分数。 |
| `sidebar <玩家名> remove <objective> <entry>` | 删除一行分数。 |
| `sidebar <玩家名> hide <objective>` | 隐藏右侧计分板。 |
| `particle <玩家名> <粒子> <x> <y> <z> ...` | 向指定玩家发送粒子效果。 |

## 活动存档切换

查看当前唯一的活动存档：

```text
world current
```

保持在线玩家连接并切换到另一个存档：

```text
world load arena
```

该命令直接使用原版 Java 世界目录 `arena/`，区块位于 `arena/region/*.mca`，
种子和世界元数据位于 `arena/level.dat`；目录不存在时会自动创建。切换期间会保存并停止旧
世界区块任务、重载 Lua 插件、清除普通实体、向所有玩家发送 Respawn、传送
到新出生点并重新发送区块。世界名只允许字母、数字、`_` 和 `-`。

## 1. 服务端与玩家

Minecraft 客户端进入 Play 后会收到权限过滤后的 `/` 命令列表。客户端执行
命令时发送 protocol 775 `Chat Command` 请求，与控制台共用同一个命令注册表。
默认玩家可以使用 `help`、`list`、`where`；在控制台授予在线 OP：

```text
op Latos_
deop Latos_
```

权限变化后客户端命令列表会立即刷新，不需要重新连接。OP 状态当前只在本次
在线会话中有效。

```text
help
list
say OakMC 测试开始
where Latos_
tp Latos_ 100 68 0
tp Latos_ 100 68 0 180 0
gamemode Latos_ survival
gamemode Latos_ creative
sethealth Latos_ 20 20 5
kick Latos_
reload
reload-lua
stop
```

`reload` 会在保留在线连接的情况下重载配置和 Lua；如果 `level-name` 改变，
还会无缝切换活动存档。`reload-lua` 只重载 Lua；`stop`
会直接停止服务端，放在整组测试的最后执行。

转移到另一台服务端：

```text
transfer Latos_ 127.0.0.1 25566
```

## 2. 物品与自定义名称

给当前选中的快捷栏槽位发送物品：

```text
give Latos_ minecraft:stone
give Latos_ stone 64
give Latos_ apple 1 "测试苹果"
give Latos_ stone 1 "{CustomName:'测试石头'}"
give Latos_ diamond_sword 1 "{\"text\":\"JSON名称\"}"
```

直接设置指定背包槽位，当前槽位范围为 `0..35`：

```text
setitem Latos_ 0 stone 64
setitem Latos_ 1 apple 1 "{CustomName:'第二格物品'}"
setitem Latos_ 8 diamond_sword 1 "{CustomName:'快捷栏末格'}"
```

当前可解析的 `nbt_data` 只覆盖物品 `minecraft:custom_name`，可以直接传
普通文本，也可以传 `{CustomName:'文本'}` 简写或 JSON Text Component。
`give` 和 `setitem` 的物品参数只接受注册名，不接受数字物品 ID。
它不是任意原始 NBT 透传；无法识别的输入会返回错误，不会向客户端发送
无效 ItemStack。

## 3. 实体生成

按实体 registry 名生成：

```text
spawn minecraft:villager 100 68 4
spawn minecraft:zombie 102 68 4
spawn minecraft:item_frame 100 69 6
spawn minecraft:villager 100 68 4 {"text":"命名村民","color":"gold","bold":true}
```

指定身体 yaw、pitch 和 head yaw：

```text
spawn minecraft:villager 100 68 4 180 0 180
spawn minecraft:zombie 102 68 4 90 0 90
spawn minecraft:villager 100 68 4 180 0 180 0 {"text":"守卫","color":"red"}
```

最后一个参数是 Add Entity packet 的 `data` 字段：

```text
spawn minecraft:item_frame 100 69 6 0 0 0 3
```

也可以直接使用当前版本的实体类型数字 ID：

```text
spawn 139 100 68 4
```

控制台会打印新分配的 `entity_id`。第五个参数或完整参数组的最后一个
参数可以是紧凑 JSON Text Component；spawn 会在 Add Entity 后自动发送
自定义名称 metadata。后续改名可以直接使用本文第 7 节的 Lua 调用；持续旋转
示例见 `scripts/example/example_villager_look.lua`。

## 4. 方块、天气与声音

第四个参数可以是方块注册名，也可以是数字 block state id。注册名会使用该方块的
默认 state；`stone` 和 `minecraft:stone` 都可用：

```text
block 100 67 0 minecraft:stone
block 101 67 0 1
```

天气持续时间使用 tick，`1200 tick` 约为 60 秒：

```text
weather clear 1200
weather rain 1200
weather thunder 600
```

按 sound registry 名播放声音，category `0` 为 master：

```text
playsoundname Latos_ minecraft:entity.player.levelup 0
playsoundname Latos_ minecraft:entity.villager.celebrate 0 1.0 1.0 0
```

也可以直接使用当前版本的 sound registry 数字 ID：

```text
playsound Latos_ 1 0 1.0 1.0 0
```

## 5. 状态效果与标题

效果等级使用零基 amplifier，因此 `1` 表示 II 级效果：

```text
effect Latos_ speed 1 30 icon
effect Latos_ night_vision 0 infinite particles,icon
effect Latos_ regeneration 0 10 ambient,particles,icon
```

标题时间单位同样是 tick：

```text
title Latos_ times 10 70 20
title Latos_ title 欢迎来到 OakMC
title Latos_ subtitle Minecraft 26.1.2
title Latos_ title {"text":"金色标题","color":"gold","bold":true}
title Latos_ subtitle {"text":"带格式的副标题","color":"yellow","italic":true}
title Latos_ clear
title Latos_ clear true
```

## 6. 右侧排名榜与粒子

创建右侧榜单、写入/更新分数、删除条目并隐藏榜单：

```text
sidebar Latos_ show rank 在线排名
sidebar Latos_ set rank alice 100 Alice
sidebar Latos_ set rank bob 80 Bob
sidebar Latos_ update rank 本周排名
sidebar Latos_ remove rank bob
sidebar Latos_ hide rank
```

生成只对目标玩家可见的粒子。下面依次是默认单个火焰，以及带数量、偏移和
速度的粒子簇：

```text
particle Latos_ flame 0 80 0
particle Latos_ happy_villager 0 80 0 20 0.5 1.0 0.5 0.05 true false
```

控制台命令只接受不需要额外 ParticleOptions 数据的粒子；`block`、`dust`、
`item`、`vibration`、`trail` 等复杂类型会被拒绝，避免发送不完整数据包。

## 7. BossBar、GUI 与实体名称

当前控制台没有 `bossbar` 和 GUI 命令，这些功能由 Lua/C API
提供。下面是可以放入插件 `init()` 的 JSON Text Component 调用片段；执行前请把
`Latos_` 改成实际在线玩家名：

```lua
local name = "Latos_"
local boss_uuid = "00000000-0000-4000-8000-000000000101"

mcs_title_set_text(
    name,
    '{"text":"金色标题","color":"gold","bold":true}'
)

mcs_player_boss_bar_add(
    name,
    boss_uuid,
    '{"text":"红色 BossBar","color":"red","bold":true}',
    1.0,
    MCS_BOSS_BAR_COLOR_RED,
    MCS_BOSS_BAR_DIVISION_10,
    0
)

mcs_player_open_screen(
    name,
    10,
    0,
    '{"text":"金色 GUI","color":"gold","bold":true}'
)

mcs_player_set_screen_slot(
    name,
    10,
    0,
    0,
    1,
    1,
    '{"text":"蓝色物品","color":"aqua","italic":false}'
)
```

title、BossBar、GUI 标题和实体名称都兼容普通文本；当参数是合法 JSON Text
Component 时，OakMC 会递归转换为网络 NBT。GUI slot 的最后一个参数属于
ItemStack `minecraft:custom_name` 路径，也可以使用同样的直接 JSON 格式。
格式错误的 `{...}`、`[...]` 或引号字符串会被拒绝，避免向客户端发送无法
解码的 component。

玩家名称有两个不同入口：

```lua
-- Player Info/tab 名称，传普通 profile name。
mcs_player_set_custom_name("Latos_", "ServerPlayer", true)

-- 世界内名牌前缀，支持普通文本或 JSON Text Component。
mcs_player_set_custom_prefix_name(
    "Latos_",
    '{"text":"[OakMC] ","color":"gold"}',
    true
)
```

`mcs_player_set_custom_name` 不会修改服务端用于查找玩家的登录用户名；
`mcs_player_set_custom_prefix_name` 会把前缀放在原登录用户名之前。

把这些调用放入一个返回 `{ name, depends, init }` 的 `plugins/*.lua` 模块，
然后执行：

```text
reload-lua
```

调用成功后，目标玩家会看到：

- JSON Text Component 标题
- 带自定义名称物品的 9 格 GUI
- 指定标题、血量、颜色、分段样式和 flags 的 BossBar
- 分别通过 Player Info 和 scoreboard team prefix 设置的玩家显示名
