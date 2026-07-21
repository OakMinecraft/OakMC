# OakMC Lua API Reference

[中文](lua-api-reference-zh.md)

OakMC embeds Lua 5.4 for gameplay plugins and server-side experiments. Lua
plugins are discovered from `plugins/*.lua`, validated as a dependency graph,
and initialized in topological order. `reload-lua` calls shutdown hooks in
reverse dependency order, unregisters Lua events, recreates the VM, and loads
plugins again without kicking players or reloading `server.properties`.

`reload` also reloads Lua while preserving player connections. When
`level-name` changes, or when `world load <name>` is executed, OakMC calls the
old world's plugin `shutdown()` hooks in reverse dependency order, unregisters
Lua events, removes generic runtime entities, switches the active save, and
then runs plugin `init()` hooks in dependency order for the new world. Plugins
must not assume Lua globals survive a world switch; persistent data should be
stored explicitly by the plugin.

This document describes the Lua-facing API. For C runtime helpers, see
`docs/runtime-api-reference.md`. For copyable scenario scripts, see
`scripts/example/`.

## Client Audience Semantics

Client-visible actions describe who receives the display packet, not
necessarily which entity or player is being changed. These actions use three
explicit audience forms. In normalized unsuffixed functions, `viewer_name` or
`playername` means the packet is sent only to that player's client. Functions
ending in `_for_others(owner_entity_id, ...)` send to every initialized client
except the owner of that entity. Functions ending in `_for_all(...)` send to every
initialized client, including the owner. For example, in equipment display APIs,
`viewer_name` is the player who sees the equipment change, while `entity_id` is
the entity whose equipment is displayed. State-mutating APIs such as health,
inventory, gamemode, effects, flight, and transfer remain player-targeted and
continue to use `playername`; they are not broadcasts. Legacy names remain as
compatibility entry points so existing plugins do not change behavior silently.
Some legacy exceptions, notably `mcs_player_swing_hand(playername, hand)` and
the Lua logging alias `mcs_chat_send_system_message`, retain their historical
behavior; new code should use the explicit audience forms.

The normalized client-visible families are system chat, equipment display, hurt animation,
bow animation, arm swing, title/subtitle/action bar, particles, sidebar
scoreboards, boss bars, and sounds. For example,
`mcs_title_set_text_for_all(text)`, `mcs_chat_send_system_message_for_all(message)`,
`mcs_particle_spawn_for_others(owner_entity_id, ...)`,
`mcs_scoreboard_sidebar_set_score_for_all(...)`,
`mcs_player_boss_bar_update_health_for_others(owner_entity_id, ...)`, and
`mcs_player_play_sound_for_all(...)` all follow the same rule.

## 1. Loading Model

- Plugin directory: `plugins/*.lua`
- Editor/type stub: `scripts/oakmc_api.lua`
- Example scripts: `scripts/example/*.lua`
- Reload command: `reload-lua`

Each plugin returns `{ name, depends, init, shutdown }`. `depends` contains
plugin names and is optional; `init` is required; `name` and `shutdown` are
optional. Missing, duplicate, self, and circular dependencies are rejected
before initialization. To use an example, copy it into `plugins/` and run
`reload-lua`.

Example with more than one dependency:

```lua
return {
    name = "economy",
    depends = {"core1", "core2"},
    init = init,
    shutdown = shutdown,
}
```

Plugin loading is deliberately split into separate phases:

1. Execute every `plugins/*.lua` file and collect its returned module table.
2. Resolve every name in every `depends` array against the complete plugin
   collection.
3. Validate the complete graph and build an order where `core1` and `core2`
   appear before `economy`.
4. Only after every plugin and dependency succeeds, call `init()` in that
   order.

Dependency resolution records an order; it does not call `init()` while
searching. If one dependency is missing or a cycle is found anywhere in the
graph, no plugin `init()` is called, even if part of the order had already been
calculated. A plugin with several dependencies is added to the order only
after all of them have been resolved. A shared dependency is recorded and
initialized only once.

All plugin files are executed during the collection phase, before dependency
validation. Top-level plugin code should therefore only define functions and
module data. Event registration and other side effects belong in `init()`.

## 2. Return Values

Most Lua helpers return `true` on success and `false` on failure. Lookup
helpers return a table on success and `nil` when the target does not exist or
cannot be represented by the current API.

Important exceptions:

- `mcs_block_get_state(x, y, z)` returns a block state id.
- `mcs_block_state_id_from_name(block_name)` returns the default block state id,
  or `nil` when the block name is unknown.
- `mcs_block_is_solid(x, y, z)` and
  `mcs_block_state_is_solid(block_name_or_state_id)` return booleans.
- `mcs_entity_spawn(...)` returns the newly allocated runtime `entity_id`, or
  `nil` on failure.
- `mcs_player_count()` returns the number of online players.
- `mcs_player_get_gamemode(playername)` returns a gamemode id or `nil`.

### 2.1 Text Component And Item Name Inputs

The text-bearing APIs use two related but distinct input paths:

- title/subtitle/Action Bar text, BossBar titles, GUI titles, entity custom
  names, and the optional entity-spawn name accept ordinary text or a JSON
  Text Component
- item-bearing APIs accept optional `nbt_data`, but the current implementation
  maps it only to the ItemStack `minecraft:custom_name` component
- item custom names may be plain text, `{CustomName:'text'}`, or a direct JSON
  Text Component such as
  `{"text":"Named item","color":"aqua","italic":false}`
- `nil` or an empty string adds no item components
- this is not arbitrary raw NBT support; malformed or unsupported
  JSON/NBT-looking input is rejected before a packet is sent

## 3. Function Reference

### 3.1 Server And Chat

```lua
mcs_server_send_message(message, log_type)
mcs_server_shutdown()
mcs_server_get_port()
mcs_server_port_is_available(port)
mcs_server_find_available_port([start_port])
mcs_server_start_instance(instance_name, port [, remote_port [, allowed_commands]])
mcs_server_start_instance_from(template_name, instance_name, port
    [, remote_port [, allowed_commands]])
mcs_server_delete_current_instance()
mcs_server_query_status(address, port)
mcs_server_file_lock(path, timeout_ms)
mcs_server_file_unlock(lock_id)
mcs_command_register(command, usage, description, need_op, callback)
mcs_chat_send_system_message(message, log_type)
mcs_chat_send_system_message_to_player(playername, message)
mcs_chat_send_system_message_all_player(message)
mcs_remote_command_send(target_id, address, port, command)
mcs_remote_is_enabled()
```

`log_type` uses the `MCS_LOG_*` constants. The current
`mcs_chat_send_system_message` Lua binding is a compatibility alias for the
server log helper. `mcs_chat_send_system_message_to_player` sends a normal
system-chat message only to the named online player, while
`mcs_chat_send_system_message_all_player` broadcasts one to all online players.

`mcs_server_shutdown()` requests a graceful shutdown of the current server and
returns a boolean. The runtime handles the request after the current Lua callback
returns: the startup path handles requests made during plugin initialization,
and the tick thread handles requests made while the server is running. Dirty
chunks are flushed, plugin `shutdown()` callbacks run in reverse order, and the
remote command bridge stops. Do not schedule work that depends on later ticks
after submitting the request.

`mcs_server_get_port()` returns the effective listen port, including a command-line
override. `mcs_server_start_instance(instance_name, port [, remote_port
[, allowed_commands]])` starts the current OakMC executable in
`instances/<instance_name>/` and waits until its loopback port accepts
connections. Instance names may contain only letters, digits, hyphens, and
underscores. Startup never carries economy, announcement, player, or other
application data. Use `mcs_remote_command_send` and the signed remote bridge for
cross-server state or command synchronization.

When `remote_port` is supplied, C requests a child Remote listener whose
`server-id` is `instance_name`. It writes the parent's effective secret to a
reserved permission-restricted file inside the instance directory and passes
that file to the child process; Lua never receives the secret. If the parent has
no valid Remote secret, the same child starts normally with Remote disabled.
`allowed_commands` is optional and defaults to an empty incoming allow-list.
Pass comma-separated command tokens without spaces, for example `stop,say`.

`mcs_server_start_instance_from(template_name, instance_name, port
[, remote_port [, allowed_commands]])` creates a dynamic room by copying
`instances/<template_name>/` into a new isolated `instances/<instance_name>/`
directory before launching it. The copy excludes `log/`, `crashes/`,
`remote.properties`, and the reserved instance secret file so rooms do not
inherit stale logs or credentials or contend for the template's Remote
listener; the world, plugins, and `server.properties` are copied independently.
Its optional Remote arguments have the same behavior as the non-template form.

`mcs_server_query_status(address, port)` performs a standard Minecraft Status
query against an IPv4 server. It returns `online_players, max_players` on
success, or `nil` when the connection, protocol response, or player fields are
invalid. The call is synchronous, so plugins should avoid issuing large batches
of status queries from a server-tick callback.

`mcs_server_delete_current_instance()` is accepted only inside a dynamic room
created and marked by `mcs_server_start_instance_from()`. It schedules graceful
shutdown; after saving the world, unloading plugins, and stopping Remote, the
runtime leaves the working directory and recursively deletes the room. Calls
from the main server, a template directory, or a regular
`mcs_server_start_instance()` child return `false` without deleting files.

`mcs_server_find_available_port(start_port)` performs real TCP bind probes from
the requested starting port through `65535`, returning the first available port
or `nil`. The default start is `10000`. Callers should still handle
`mcs_server_start_instance` failure because another process can claim the port
between probing and child startup.

`mcs_server_port_is_available(port)` performs the same bind probe for exactly one
port and returns a boolean. It does not connect to a Minecraft server or query
player status. A `true` result means the port can currently be bound; `false`
usually means another local listener owns it, although socket or bind errors
also produce `false`. It is intended for checking or allocating a local listen
port; it does not identify which process owns an occupied port or provide child
lifecycle state.

`mcs_server_file_lock(path, timeout_ms)` obtains a cross-process exclusive lock
and returns an integer lock id, or `nil` on timeout/error. Release a successful
lock with `mcs_server_file_unlock(lock_id)`; the operating system also releases
it if the process exits.

`mcs_remote_command_send(target_id, address, port, command)` sends to the
dynamically supplied IPv4 address and Remote listener port. `target_id` must
match the receiver's `server-id`. The sender identity and cluster secret come
from the merged Remote runtime configuration; startup options and
`OAKMC_REMOTE_SECRET` can override the sender's local `remote.properties`. No
outgoing peer is configured in that file. The function returns
`success, response`: an accepted request returns
`true, "OK"`, an explicit rejection returns `false, "ERR"`, and a transport or
configuration failure returns `false, nil`. Tokens, nonces, and HMAC material
are never exposed to Lua.

`mcs_remote_is_enabled()` returns whether the current process has a valid,
enabled Remote configuration.

```lua
local ok, response = mcs_remote_command_send(
    "survival", "127.0.0.1", 25576, "say Hello from hub"
)
if not ok then
    mcs_server_send_message("remote command failed: " .. (response or "unavailable"), MCS_LOG_WARN)
end
```

`mcs_command_register(...)` adds a native server command. It is visible in
`help`, uses the normal OP check, and is sent to Minecraft clients as part of
the Brigadier command tree. Registrations are removed automatically before the
Lua VM closes, including during `reload-lua`, `reload`, and world switches.

The callback receives `context, args`. `args` is a 1-based array without the
command name. `context.is_console`, `context.is_op`, and `context.source` are
always present. Player execution also provides `playername`/`username`, `uuid`,
`entity_id`, and `fd`. Authenticated remote commands use the console/OP context.
Return `false` to reject the invocation and show the registered usage; `true`
or `nil` means success. The command token must not include `/` or whitespace,
and neither built-in nor previously registered names can be replaced.

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
    "Show a Lua-provided greeting",
    false,
    hello
))
```

### 3.2 Blocks

```lua
mcs_block_place(playername, x, y, z, block_name_or_state_id)
mcs_block_broadcast_update(x, y, z, block_name_or_state_id)
mcs_block_get_state(x, y, z)
mcs_block_state_id_from_name(block_name)
mcs_block_is_solid(x, y, z)
mcs_block_state_is_solid(block_name_or_state_id)
mcs_block_set_break_animation(playername, animation_id, x, y, z, stage)
```

`mcs_block_place` mutates server-side block state and sends the change only to
`playername`. Loop over `mcs_player_list_info()` to send it to multiple viewers.
`mcs_block_broadcast_update` only sends a visual single-block update to
connected clients; it does not mutate server world state. That is useful when
rolling back a cancelled client action.

The block-state arguments accept either the existing integer id or a block
registry name such as `stone`, `minecraft:oak_stairs`, or `Grass Block`.
Names resolve to the block's default 26.1.2 state. Use
`mcs_block_state_id_from_name` when the numeric id itself is needed; it returns
`nil` for unknown names.

`mcs_block_set_break_animation` sends the client-side crack overlay only to
`playername` without changing the block. `stage` is `0..9`; pass `-1` to clear
it. Reuse the same `animation_id` when advancing or clearing one overlay.

### 3.3 Entities

```lua
mcs_entity_spawn(entity_type_id, x, y, z, yaw, pitch, head_yaw, data [, name_component])
mcs_fake_player_add(username, uuid, x, y, z, yaw, pitch, listed, texture_value [, texture_signature])
mcs_fake_player_set_name_visible(entity_id, visible)
mcs_entity_spawn_with_velocity(entity_type_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, head_yaw, data)
mcs_entity_set_custom_name(entity_id, name, visible)
mcs_entity_rotate(entity_id, x, y, z, yaw, pitch, head_yaw)
mcs_entity_move(entity_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, head_yaw, on_ground)
mcs_entity_remove(entity_id)
mcs_entity_get_info_by_id(entity_id)
```

`mcs_entity_spawn` accepts a numeric entity type id and optional rotation/data
arguments. It broadcasts a visible entity spawn and returns the runtime
`entity_id`. `name_component` may be plain text or a JSON Text Component;
when present, OakMC immediately sends custom-name metadata after Add Entity.
The current implementation does not provide full server-side
entity AI, ticking, or persistence.

`mcs_fake_player_add` returns a runtime `entity_id` or `nil`. It sends the fake
Profile before the player entity, preserving the supplied `textures` value and
optional signature. Set `listed` to `false` to keep the skin Profile available
without showing the fake player in Tab. Existing viewers receive it
immediately; players joining or resynchronizing later receive all current fake
players automatically. The entity can be moved or removed with the normal
`mcs_entity_move` and `mcs_entity_remove` APIs, and it does not count as an
online connected player. `texture_value` is the Base64-encoded Minecraft
`textures` property value, not a skin image URL; `texture_signature` may be
omitted or `nil` for an unsigned property.

`mcs_fake_player_set_name_visible(entity_id, false)` hides the original
GameProfile name above the fake player by assigning it to a scoreboard Team
whose name-tag visibility is `never`. Pass `true` to remove that hiding Team.
The setting is retained for players who join or resynchronize later. This is
independent of `listed`, which controls only the Tab player list.

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
mcs_fake_player_set_name_visible(npc_id, false)
```

`mcs_entity_spawn_with_velocity` includes the initial velocity directly in the
Add Entity packet. Use it for projectiles that the client should simulate from
their first tick.

`mcs_entity_set_custom_name` broadcasts entity metadata for a visible custom
name and whether that nameplate should be rendered above the entity. `name`
may be plain text or a JSON Text Component.

`mcs_entity_rotate` broadcasts a visual rotation update for an already spawned
entity. `yaw`/`pitch` update the body via Entity Position Sync; `head_yaw`
updates the head via Rotate Head.

`mcs_entity_move` broadcasts position, velocity, rotation, and ground state.
Use it for projectiles and other continuously moving entities so the client can
interpolate between server ticks.

`mcs_entity_remove(entity_id)` sends Remove Entities to initialized Play
connections and unregisters the generic runtime entity. Fake players also
remove their client Profile cache; real connected player entities cannot be
removed through this API.

`mcs_entity_get_info_by_id(entity_id)` looks up by runtime entity id and
returns a generic entity snapshot. Unknown entities return `nil`.

#### Holograms

```lua
mcs_hologram_create(x, y, z, text)
mcs_hologram_set_text(entity_id, text)
mcs_hologram_move(entity_id, x, y, z)
mcs_hologram_remove(entity_id)
```

Holograms use the native `minecraft:text_display` entity. Creation returns its
runtime `entity_id`, or `nil` on failure. Text accepts plain strings or JSON
Text Components. The display is center-billboarded so it faces viewers and has
a text shadow enabled. Update, move, and remove only accept text-display ids;
the generic `mcs_entity_remove` API can also remove one.

```lua
local id = mcs_hologram_create(0.5, 66.5, 0.5,
    '{"text":"OakMC","color":"gold","bold":true}')
if id then
    mcs_hologram_set_text(id, "Welcome!")
    mcs_hologram_move(id, 0.5, 68.0, 0.5)
end
```

### 3.4 World

```lua
mcs_world_update_weather(rain_level, thunder_level, raining)
mcs_world_set_time(time)
mcs_world_set_default_spawn_position(dimension_name, x, y, z, yaw, pitch)
```

`x`, `y`, and `z` accept fractional coordinates. Player placement preserves
the fractions; the default-spawn block sent to clients uses the containing
block (each component rounded down).

`mcs_world_update_weather` directly updates the weather presentation sent to
players. Duration countdown and next-weather scheduling stay inside the play
world implementation, not Lua.

`mcs_world_set_time(time)` sends exactly one Set Time packet to every currently
initialized player, using the non-negative tick value for both protocol time
fields. It does not store or advance the value, start a timer, update
`level.dat`, or resend it when a player joins or the world is switched. Call it
again only when another client time update is needed. This is separate from
`mcs_title_set_time`, which controls title animation durations.

There is currently no public `mcs_world_switch(...)` Lua function. Switch the
active save with the console command `world load <name>`, or change
`level-name` in `server.properties` and run `reload`. Both paths preserve
online connections and trigger the Lua `shutdown()`/`init()` lifecycle
described above.

### 3.5 Player Lookup

```lua
mcs_player_count()
mcs_player_get_info_by_name(playername)
mcs_player_get_info_by_uuid(uuid)
mcs_player_get_info_by_fd(fd)
mcs_entity_get_info_by_id(entity_id)
mcs_player_list_info()
```

`mcs_player_get_info_by_name(name)`, `mcs_player_get_info_by_uuid(uuid)`, and
`mcs_player_get_info_by_fd(fd)` are player-keyed lookups.
`mcs_entity_get_info_by_id(entity_id)` is entity-keyed
and returns `MCSEntityInfo`.

`MCSPlayerInfo` fields:

- `entity_id`
- `is_player`
- `username`
- `uuid`
- `fd`
- `play_initialized`
- `x`, `y`, `z`
- `yaw`, `pitch`
- `on_ground`
- `horizontal_collision`
- `game_mode`
- `allow_flying`
- `is_flying`
- `dimension_id`
- `health`
- `food`
- `food_saturation`
- `selected_inventory_id`
- `awaiting_teleport`
- `pending_teleport_id`
- `last_keep_alive_ms`
- `pending_keep_alive_id`
- `is_jump`
- `hidden`
- `is_op`

`MCSEntityInfo` fields:

- `entity_id`
- `kind`
- `entity_type_id`
- `x`, `y`, `z`
- `yaw`, `pitch`, `head_yaw`
- `data`
- `custom_name_visible`
- `custom_name`

### 3.5.1 Whitelist And Bans

```lua
mcs_whitelist_add(identity)
mcs_whitelist_remove(identity)
mcs_whitelist_contains(identity)

mcs_ban_add(identity)
mcs_ban_add(username, uuid)
mcs_ban_remove(identity)
mcs_ban_contains(identity)

mcs_ban_ip_add(ip)
mcs_ban_ip_remove(ip)
mcs_ban_ip_contains(ip)
```

`identity` accepts either a username or a canonical UUID. Mutations are
persisted to the same JSON files used by the built-in commands. Player bans
kick a matching online player; IP bans best-effort kick every currently
logged-in player using that IPv4 address and reject future connections.

### 3.6 Player Control

```lua
mcs_player_kick(playername)
mcs_player_tp_by_name(playername, x, y, z, yaw, pitch)
mcs_player_sync_position_with_velocity(playername, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch)
mcs_player_transfer(playername, host, port)
mcs_player_send_custom_payload(playername, channel, payload)
mcs_player_set_gamemode(playername, gamemode)
mcs_player_set_custom_name(playername, name, visible)
mcs_player_set_custom_prefix_name(playername, prefix, visible)
mcs_player_hide(playername [, viewername])
mcs_player_show(playername [, viewername])
mcs_player_set_op(playername, is_op)
mcs_player_get_gamemode(playername)
mcs_player_update_health(playername, health, food, food_saturation)
mcs_player_set_armor_value(playername, armor)
mcs_player_set_experience(playername, progress, level, total_experience)
mcs_player_set_allow_flying(playername, allow_flying)
mcs_player_set_flying_speed(playername, flying_speed)
mcs_player_set_held_item_display(entity_id, hand, item_id [, count [, nbt_data]])
mcs_player_set_equipment_display(viewer_name, entity_id, equipment_slot, item_id [, count [, nbt_data]])
mcs_player_set_equipment_display_for_others(entity_id, equipment_slot, item_id [, count [, nbt_data]])
mcs_player_set_equipment_display_for_all(entity_id, equipment_slot, item_id [, count [, nbt_data]])
mcs_player_set_bow_animation(playername, entity_id, pulling [, hand])
mcs_player_set_bow_animation_for_others(entity_id, pulling [, hand])
mcs_player_set_bow_animation_for_all(entity_id, pulling [, hand])
mcs_player_swing_hand(playername [, hand])
mcs_player_swing_hand_for_others(entity_id [, hand])
mcs_player_swing_hand_for_all(entity_id [, hand])
mcs_player_hurt_animation_for_others(entity_id, yaw)
mcs_player_hurt_animation_for_all(entity_id, yaw)
```

`gamemode` can be one of the numeric `MCS_GAMEMODE_*` constants or one of the
strings `"survival"`, `"creative"`, `"adventure"`, or `"spectator"`.

`mcs_player_transfer(playername, host, port)` sends a transfer packet to a
client and makes that client establish another Minecraft connection. `port` is
optional. This is different from switching between backend servers inside an
existing Velocity connection.

`mcs_player_send_custom_payload(playername, channel, payload)` sends a Play
Custom Payload. `payload` is a binary-safe Lua string; OakMC neither prefixes
an inner length nor interprets its contents. The channel protocol defines the
payload format. A single payload is limited to 32 KiB.

The optional OakMC Velocity Bridge builds on that generic API for
Velocity-internal switching. A compatible bridge must be installed on the
proxy; it consumes the control message before it can reach the Minecraft
client. Application plugins can encode this channel protocol:

```text
channel = oakmc:proxy_transfer

version:u8 (=1)
server_name:u16-be length + UTF-8
host:u16-be length + UTF-8
port:u16-be
```

Choose a stable Velocity `server_name` independently from the unique OakMC
process instance name. A port-derived name is sufficient only when all dynamic
targets share one fixed host. Deployments with multiple target hosts that can
reuse the same port must include a stable host identifier so two different
addresses never share one Velocity registration key. The application plugin
owns the encoder, target selection, and backend lifecycle policy. See
`integrations/velocity-bridge/README.md` for the complete bridge contract.

`mcs_player_set_experience` updates the experience HUD. `progress` is the
filled bar fraction in `0.0..1.0`; `level` is displayed above the bar; `level`
and `total_experience` must be non-negative integers.

`mcs_player_set_allow_flying(playername, true)` lets a survival or adventure
player start flying by double-tapping jump without changing their gamemode.
Passing `false` revokes the extra permission and stops active flight. Creative
and spectator flight remains available because it is provided by the
gamemode. The setting lasts for the current online session only. Player info
exposes the extra permission as `allow_flying` and the latest client-reported
flight state as `is_flying`.

The two player-name helpers intentionally target different client surfaces:

- `mcs_player_set_custom_name` stores the supplied name and, when `visible` is
  true, re-broadcasts the Player Info entry with that profile name. This is the
  player-info/tab path. The value is a plain profile-name string, not a JSON
  Text Component, and it must fit the protocol username limit. When `visible`
  is false, the value is only stored and no Player Info update is sent.
- `mcs_player_set_custom_prefix_name` sends entity custom-name metadata and a
  scoreboard-team prefix for the in-world player nameplate. The prefix accepts
  plain text or a JSON Text Component. Passing `visible == false` removes the
  generated team.

Neither helper changes the login username used by
`mcs_player_get_info_by_name(...)` and other server-side lookups.

`mcs_player_hide(playername)` sends Remove Entities for that player to other
initialized Play clients and continues suppressing later entity spawns and
movement broadcasts. The connection, PlayerManager entry, inventory, chunk
streaming, and tab-list entry remain active. `mcs_player_show(playername)`
clears the hidden state and re-sends the player entity, skin-parts metadata,
and custom-name team state to other clients. Both calls are idempotent.

Passing `viewername` changes only that viewer: `mcs_player_hide(target, viewer)`
removes `target` from `viewer`, while `mcs_player_show(target, viewer)` restores
it. The runtime keeps this directional relation for later movement and entity
resynchronization during the current online session. A directional hide does
not set the target's global `hidden` player-info field.

`mcs_player_set_op(playername, is_op)` grants or revokes operator permission
for an online player's current session. The change takes effect immediately
and re-sends that player's command tree. It is not persisted across reconnects;
the call returns `false` when the player is not online or the command tree
cannot be sent.

The visual-action helpers send client-visible entity state:

- `mcs_player_set_held_item_display` sends `Set Equipment` for any registered
  `entity_id`. `hand` is `0` for main hand and `1` for offhand. The entity
  manager retains the visual item for later joins, without mutating a connected
  player's tracked inventory; pass count `0` or air to clear the visual.
- `mcs_player_set_equipment_display` sends every equipment slot only to the
  specified `viewer_name`: `0` main
  hand, `1` offhand, `2` boots, `3` leggings, `4` chestplate, `5` helmet, and
  `6` body equipment. It broadcasts and persists visual equipment but does not
  mutate the real inventory or automatically calculate armor damage reduction.
- `mcs_player_set_equipment_display_for_others` uses the same slots but skips
  the real player who owns the entity. It is intended for held-item broadcasts
  where a delayed server packet must not overwrite the owner's local scroll.
- `mcs_player_set_equipment_display_for_all` sends the equipment to every
  current viewer, including the entity owner.
- `mcs_player_set_bow_animation` starts or stops the Living Entity active-hand
  pose for `entity_id`, only on the client named by `playername`. Show a bow
  with `mcs_player_set_held_item_display` first if needed. Loop over
  `mcs_player_list_info()` when every viewer should receive the pose.
- `mcs_player_swing_hand` sends the arm-swing animation used by both block
  placement and block breaking. For a full break effect, combine it with
  `mcs_block_set_break_animation`; for placement, combine it with
  `mcs_block_place` or `mcs_block_broadcast_update`.

```lua
local entity_id = mcs_player_get_info_by_name("Steve").entity_id
mcs_player_set_held_item_display(entity_id, 0, 895, 1) -- 26.1.2 bow item id
mcs_player_set_bow_animation("Steve", entity_id, true, 0)
mcs_player_swing_hand("Steve", 0)
mcs_block_set_break_animation("Steve", 123, 10, 64, 10, 5)
```

### 3.7 Inventory

```lua
mcs_player_set_inventory_item(playername, inventory_id, item_id_or_name, count [, nbt_data])
mcs_player_give_item(playername, inventory_id, item_id_or_name, count [, nbt_data])
mcs_player_get_inventory_info(playername, inventory_id)
mcs_player_inventory_is_item(playername, inventory_id)
mcs_player_inventory_is_block(playername, inventory_id)
mcs_player_inventory_is_food(playername, inventory_id)
```

`mcs_player_set_inventory_item` directly sets one tracked inventory slot.
`mcs_player_give_item` emits `MCS_EVENT_PLAYER_RECEIVE_ITEM`; Lua handlers can
cancel the give or rewrite `event.inventory_id`, `event.item_id`,
`event.count`, `event.nbt_data`, and `event.source` before the default handler updates the slot
and sends the inventory sync packet. The current runtime tracks player
inventory slots `0..35`: `0..8` are hotbar slots and `9..35` are the main
inventory. `selected_inventory_id` is still hotbar-only (`0..8`).
`item_id_or_name` may be a numeric Minecraft 26.1.2 item id or a registry
string such as `diamond_sword` or `minecraft:diamond_sword`.

`nbt_data` is optional. It may be plain text, `{CustomName:'测试'}`, or a direct
JSON Text Component such as `{"text":"测试","color":"gold","bold":true}`.
OakMC writes the 26.1.2 `minecraft:custom_name` component as a Text Component
compound. ItemStack components use the protocol's direct component codec; no
extra per-component payload length is inserted. Passing `nil` or `""` keeps the
added and removed component lists empty. Other NBT tags are not implemented and
unsupported input is rejected instead of being sent as an invalid ItemStack.

`mcs_player_get_inventory_info(...)` returns `nil` on failure, otherwise:

- `inventory_id`
- `used`
- `is_item`
- `is_block`
- `is_food`
- `item_id`
- `block_state_id`
- `count`

`is_item` means the slot is non-empty. `is_block` follows the local Minecraft
`26.1.2` `BlockItem` registration table, so it answers whether the held item is
a block item even if OakMC does not yet implement every special placement path.
`is_food` follows the local Minecraft `26.1.2` food/component list; for example
wheat and eggs are items, but not food.

Example for a right-click handler:

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

### 3.8 Effects And Damage

```lua
mcs_player_set_effect(playername, effect_id_or_name, amplifier, duration_or_infinite, flags)
mcs_player_apply_damage(target, source_entity_id, amount, damage_cause)
```

Lua effect durations are user-facing seconds, matching the built-in `effect`
command. Use the string `"infinite"` for an infinite effect.

Examples:

```lua
mcs_player_set_effect("Steve", "speed", 1, 30, "icon")
mcs_player_set_effect("Steve", MCS_EFFECT_SPEED, 254, 60, "icon")
mcs_player_set_effect("Steve", "night_vision", 0, "infinite", "particles,icon")
```

Effect `amplifier` is the protocol amplifier, so it is zero-based. For example,
Speed II uses amplifier `1`; Speed 255 uses amplifier `254`.

### 3.9 Screen And Boss Bar

```lua
mcs_player_open_book(playername [, pages])
mcs_player_open_written_book(playername, pages)
mcs_player_open_book_with_title(playername, title, pages)
mcs_player_open_book_with_author(playername, author, pages)
mcs_player_open_book_components(playername, title, author, page_components)
mcs_player_open_screen(playername, window_id, inventory_type, title)
mcs_player_set_screen_slot(playername, container_id, state_id, slot_id, item_id, count [, nbt_data])
mcs_player_boss_bar_add(playername, uuid, title, health, color, dividers, flags)
mcs_player_boss_bar_remove(playername, uuid)
mcs_player_boss_bar_update_health(playername, uuid, health)
mcs_player_boss_bar_update_style(playername, uuid, color, dividers)
mcs_player_boss_bar_update_flags(playername, uuid, flags)
```

`mcs_player_open_book` force-opens the book GUI without requiring a held book.
The optional `pages` value may be one string or an array of `1..100` strings.
Each page may contain up to 1024 UTF-8 characters and 4096 encoded bytes.
OakMC temporarily displays a writable book with
`minecraft:writable_book_content` in the selected main-hand slot, sends the
protocol 775 Open Book packet, then restores the original client slot after a
short delay. The tracked server inventory is unchanged.

The four written-book helpers open the read-only signed-book GUI. `pages` and
`page_components` may be one string or an array of `1..100` strings. Their page
limits are the same as `mcs_player_open_book`. `mcs_player_open_written_book`
uses `OakMC` as both title and author; the title/author variants replace one
field and keep `OakMC` for the other. Titles allow `1..32` UTF-8 characters and
128 encoded bytes; authors allow `1..16` UTF-8 characters and 64 encoded bytes.

The regular written-book helpers encode pages as literal text, so JSON-looking
strings remain visible JSON text. `mcs_player_open_book_components` instead
accepts plain text or JSON Text Components, enabling styling and client-
supported click or hover events. Every book helper uses the same temporary
client-only main-hand slot and delayed restoration; none changes tracked server
inventory.

`mcs_player_open_screen` sends the clientbound Open Window/Open Screen packet.
`window_id` is the server-chosen container id and `inventory_type` is the
protocol menu type registry id for the current Minecraft version. This only
opens the client GUI; slot contents and click handling are separate container
packets/events. `title` may be plain text or a JSON Text Component.

`mcs_player_set_screen_slot` sends the clientbound Container Set Slot packet for
one opened GUI slot. It does not mutate the player's tracked inventory.
Use the same `container_id` as `mcs_player_open_screen`; `state_id` can start at
`0` for simple visual-only menus. Its optional `nbt_data` follows the same
ItemStack `minecraft:custom_name` rules as inventory and give helpers.

Example:

```lua
mcs_player_open_book("Steve", "Welcome to OakMC!")
mcs_player_open_book("Steve", {
    "Page 1: Welcome to OakMC!",
    "Page 2: This text was supplied by Lua.",
})
mcs_player_open_written_book("Steve", {"Read-only page 1", "Page 2"})
mcs_player_open_book_with_title("Steve", "Server Guide", {"Welcome", "Rules"})
mcs_player_open_book_with_author("Steve", "Latos", "Written by Latos")
mcs_player_open_book_components(
    "Steve",
    "OakMC Guide",
    "OakMC",
    {
        '{"text":"Welcome","color":"gold","bold":true}',
        '{"text":"Run help","click_event":{"action":"run_command","command":"/help"}}',
    }
)

local WINDOW_ID = 1
local MENU_TYPE_GENERIC_9X1 = 0

mcs_player_open_screen("Steve", WINDOW_ID, MENU_TYPE_GENERIC_9X1, "OakMC Menu")
mcs_player_set_screen_slot("Steve", WINDOW_ID, 0, 0, 1, 1, nil)
```

Boss bar UUIDs are normal textual UUID strings, for example
`"00000000-0000-4000-8000-000000000001"`. `health` is `0.0..1.0`.
Boss bar titles, title/subtitle/Action Bar text, GUI titles, entity custom names,
and spawn names accept the same plain-text-or-JSON Text Component format. Item
custom names use the related `nbt_data` path described above and currently map
only to `minecraft:custom_name`.

```lua
mcs_title_set_text("Steve", '{"text":"Title","color":"gold","bold":true}')
mcs_player_open_screen("Steve", 1, 0, '{"text":"Menu","color":"blue"}')
mcs_player_set_screen_slot(
    "Steve", 1, 0, 0, 1, 1,
    '{"text":"Named item","color":"aqua","italic":false}'
)
```

Useful constants:

- `MCS_BOSS_BAR_COLOR_PINK`, `MCS_BOSS_BAR_COLOR_BLUE`,
  `MCS_BOSS_BAR_COLOR_RED`, `MCS_BOSS_BAR_COLOR_GREEN`,
  `MCS_BOSS_BAR_COLOR_YELLOW`, `MCS_BOSS_BAR_COLOR_PURPLE`,
  `MCS_BOSS_BAR_COLOR_WHITE`
- `MCS_BOSS_BAR_DIVISION_NONE`, `MCS_BOSS_BAR_DIVISION_6`,
  `MCS_BOSS_BAR_DIVISION_10`, `MCS_BOSS_BAR_DIVISION_12`,
  `MCS_BOSS_BAR_DIVISION_20`
- `MCS_BOSS_BAR_FLAG_DARKEN_SKY`, `MCS_BOSS_BAR_FLAG_DRAGON_MUSIC`,
  `MCS_BOSS_BAR_FLAG_CREATE_FOG`

### 3.10 Sound And Title

```lua
mcs_player_play_sound(playername, sound_id, category, volume, pitch, seed)
mcs_player_play_sound_name(playername, sound_name, category, volume, pitch, seed)
mcs_title_clear(playername, reset_times)
mcs_title_set_action_bar_text(playername, text)
mcs_title_set_subtitle_text(playername, text)
mcs_title_set_time(playername, fade_in, stay, fade_out)
mcs_title_set_text(playername, text)
```

`mcs_player_play_sound` uses a numeric sound id. `mcs_player_play_sound_name`
uses a registry sound name such as `minecraft:entity.player.levelup`.

Title times are measured in ticks.

Action Bar text is the small transient text above the hotbar. Send an empty
string to clear it immediately.

Legacy title aliases are still exported:

- `clear_title`
- `set_subtitle_text`
- `set_time`
- `set_title_text`

### 3.11 Sidebar And Particles

```lua
mcs_scoreboard_sidebar_show(playername, objective_name, title)
mcs_scoreboard_sidebar_update_title(playername, objective_name, title)
mcs_scoreboard_sidebar_set_score(playername, objective_name, entry_name, value, display_name [, hide_value])
mcs_scoreboard_sidebar_remove_score(playername, objective_name, entry_name)
mcs_scoreboard_sidebar_hide(playername, objective_name)
mcs_particle_spawn(playername, particle_name_or_id, x, y, z,
    offset_x, offset_y, offset_z, speed, count, force_spawn, important)
```

`objective_name` is a 1-16 byte internal key. Sidebar titles and optional
`display_name` values accept plain text or JSON Text Components. `value` still
controls row ordering. Set `hide_value=true` to use the blank number format,
or `false` to render the numeric score; omission defaults to `true`. Particle names
may be short (`flame`) or namespaced (`minecraft:flame`). Lua exposes the safe
no-extra-data particle path; data-bearing particle types, including `flash`,
are rejected.

## 4. Event API

Register handlers with:

```lua
mcs_event_register(event_type, priority, callback, options)
```

`priority` is descending: larger numbers run first.

`options` is optional:

- `options.cancellable` defaults to `true`
- `options.cancelled` defaults to `false`

Callbacks receive one table argument. Setting `event.cancelled = true` writes
back to the C event and stops later handlers when the event is cancellable. For
`MCS_EVENT_BLOCK_BREAK`, cancelling from Lua also sends the matching client ack,
so scripts can block the default break path without leaving the client digging
sequence stuck.

Common event fields:

- `type`
- `cancellable`
- `cancelled`
- `playername`
- `username`
- `entity_id`

Event-specific fields:

- `MCS_EVENT_PLAYER_CHAT`: `message`
- `MCS_EVENT_PLAYER_INITIALIZED`: emitted after the joining client has received
  existing real players, fake players, generic entities, equipment restoration,
  and skin metadata. Use this event for viewer-specific NPC animations.
- `MCS_EVENT_HELD_ITEM_CHANGE`: emitted immediately after a player changes the
  selected hotbar slot; includes `selected_inventory_id`, `item_id`,
  `block_state_id`, and `count`.
- `MCS_EVENT_SERVER_INSTANCE_CREATED`: emitted after a child instance is
  accepting connections. It includes `instance_name` and `port`; instances
  created with `mcs_server_start_instance_from()` also include `template_name`.
- `MCS_EVENT_WORLD_SPAWN_SET`: emitted after the active world's default spawn
  is successfully persisted. It includes `world_name`, `dimension_name`, exact
  `x`, `y`, `z`, floored `block_x`, `block_y`, `block_z`, `yaw`, and `pitch`.
  Invalid input and persistence failures do not emit the event.
- `MCS_EVENT_SYSTEM_CHAT`: `message`; it runs before a server System Chat
  Message is sent and can be cancelled with `event.cancelled = true`. The
  target player's common identity fields are available when present.
- `MCS_EVENT_BLOCK_BREAK`: `x`, `y`, `z`, `action`, `direction`, `sequence`, `block_state_id`
- `MCS_EVENT_BLOCK_PLACE`: `x`, `y`, `z`, `hand`, `direction`, `cursor_x`,
  `cursor_y`, `cursor_z`, `inside_block`, `world_border_hit`, `sequence`,
  `item_id`, `block_state_id`
- `MCS_EVENT_USE_ITEM`: may come from `Use Item On` or `Use Item`. The former
  carries the same block-interaction fields as `MCS_EVENT_BLOCK_PLACE`; the
  latter represents direct/in-air use and carries `hand`, `sequence`, `yaw`,
  `pitch`, `item_id`, and `block_state_id`
- `MCS_EVENT_USE_FOOD`: follows the same payload rules as `MCS_EVENT_USE_ITEM`
  but is emitted when the selected item is food; `item_id` is the selected
  hotbar item and `block_state_id` is its mapped placement state when available
- `MCS_EVENT_RELEASE_USE_ITEM`: emitted when the player stops using the active
  item (`Player Action action == 5`); carries `action`, `sequence`, `item_id`,
  and `block_state_id`, and can be used for actions such as releasing a bow
- `MCS_EVENT_SCREEN_CLICK`: `container_id`, `window_id`, `inventory_type`,
  `container_type`, `state_id`, `slot_id`, `button`, `container_input`,
  `changed_slot_count`, `first_changed_slot_id`, `first_changed_item_id`,
  `first_changed_item_count`, `carried_item_id`, `carried_item_count`
- `MCS_EVENT_PLAYER_RECEIVE_ITEM`: `inventory_id`, `item_id`, `count`, optional
  `nbt_data`, and `source`; handlers may cancel the event or rewrite those fields before the
  default inventory update runs
- `MCS_EVENT_ENTITY_ATTACK`: `target_entity_id`, `target_playername`,
  `target_username`, `attacker_entity_id`
- `MCS_EVENT_ENTITY_INTERACT`: `target_entity_id`, `target_playername`,
  `target_username`, `attacker_entity_id`
- `MCS_EVENT_SERVER_START`: currently only `type`

Listen for successfully created child instances:

```lua
local function on_instance_created(event)
    mcs_server_send_message(
        string.format("Instance %s started on port %d", event.instance_name, event.port),
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

For example, restore an NPC's bow pose only for the client that has just
finished initialization:

```lua
local function on_player_initialized(event)
    mcs_player_set_bow_animation(event.username, npc4_id, true, 0)
end

mcs_event_register(MCS_EVENT_PLAYER_INITIALIZED, 100, on_player_initialized)
```

`MCS_EVENT_PLAYER_JOIN` is intentionally earlier and is still useful for
server-side join logic. Do not use it for metadata targeting an existing NPC,
because that NPC may not have been spawned on the joining client yet.

Block break `action` follows the protocol `Player Action` values:

- `0`: start destroy block
- `1`: abort destroy block
- `2`: stop destroy block

Scripts that only want one callback per dig should usually filter on
`event.action == 0`.

Container click notes:

- `container_input` follows the protocol `ContainerInput` ids:
  `0=PICKUP`, `1=QUICK_MOVE`, `2=SWAP`, `3=CLONE`, `4=THROW`,
  `5=QUICK_CRAFT`, `6=PICKUP_ALL`.
- For normal pickup clicks, `button == 0` is left click and `button == 1` is
  right click.
- `inventory_type` / `container_type` is recorded when OakMC sends
  `mcs_player_open_screen(...)`; it is not sent again by the client click
  packet.
- The clicked slot's original item should eventually come from server-side GUI
  slot state. The current event exposes the client-reported changed slot and
  cursor-carried item, which is enough for simple menu buttons and debugging.

Example:

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

## 5. Constants

Event constants:

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

Log constants:

- `MCS_LOG_DEBUG`
- `MCS_LOG_INFO`
- `MCS_LOG_WARN`
- `MCS_LOG_ERROR`

Gamemode constants:

- `MCS_GAMEMODE_SURVIVAL`
- `MCS_GAMEMODE_CREATIVE`
- `MCS_GAMEMODE_ADVENTURE`
- `MCS_GAMEMODE_SPECTATOR`

Effect constants:

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

## 6. Copyable Mini Examples

### Join Welcome

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

### Chat Command

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

### System Chat Event

`MCS_EVENT_SYSTEM_CHAT` runs immediately before the server sends a System Chat
Message to one target connection. It exposes the outgoing text as
`event.message` and uses the common `event.playername`, `event.username`, and
`event.entity_id` fields when the target has an associated player.
For broadcasts, the event is emitted separately for each eligible target, so
cancelling one event only suppresses the message for that target. Use an exact
message comparison when only one known message should be suppressed.

```lua
mcs_event_register(MCS_EVENT_SYSTEM_CHAT, 0, function(event)
    print("system chat to " .. tostring(event.username) .. ": " .. event.message)
end)
```

Cancel matching messages without sending a replacement:

```lua
mcs_event_register(MCS_EVENT_SYSTEM_CHAT, 100, function(event)
    if event.message == "Server maintenance starts now" then
        event.cancelled = true
    end
end)
```

### Player Info Name And Nameplate Prefix

```lua
local function on_join(event)
    local player = event.playername
    if player == nil then
        return
    end

    -- Player Info/tab profile-name path: plain profile name only.
    mcs_player_set_custom_name(player, "ServerPlayer", true)

    -- In-world nameplate path: prefix is prepended to the login username.
    mcs_player_set_custom_prefix_name(
        player,
        '{"text":"[OakMC] ","color":"gold"}',
        true
    )
end

mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, on_join)
```

More complete scenarios live in `scripts/example/`.
