---@meta

---@alias MCSGamemode
---| 0 # survival
---| 1 # creative
---| 2 # adventure
---| 3 # spectator

---@alias MCSHand
---| 0 # main hand
---| 1 # offhand

---@alias MCSBossBarColor
---| 0 # pink
---| 1 # blue
---| 2 # red
---| 3 # green
---| 4 # yellow
---| 5 # purple
---| 6 # white

---@alias MCSBossBarDivision
---| 0 # none
---| 1 # 6 notches
---| 2 # 10 notches
---| 3 # 12 notches
---| 4 # 20 notches

---@class MCSPlayerInfo
---@field entity_id integer
---@field is_player boolean
---@field username string
---@field uuid string
---@field fd integer
---@field play_initialized boolean
---@field x number
---@field y number
---@field z number
---@field yaw number
---@field pitch number
---@field on_ground boolean
---@field horizontal_collision boolean
---@field game_mode MCSGamemode
---@field allow_flying boolean @ True when survival/adventure flight has been granted for this session.
---@field is_flying boolean @ The latest flying state reported by the client.
---@field dimension_id integer
---@field health number
---@field armor number @ Client-visible armor attribute used for the armor HUD bar.
---@field food integer
---@field food_saturation number
---@field selected_inventory_id integer
---@field awaiting_teleport boolean
---@field pending_teleport_id integer
---@field last_keep_alive_ms integer
---@field pending_keep_alive_id integer
---@field is_jump boolean
---@field hidden boolean @ True when the player entity is hidden from other clients; the connection and tab entry remain.
---@field is_op boolean @ True when the online player may execute commands marked need_op.

---@class MCSEntityInfo
---@field entity_id integer
---@field kind integer
---@field entity_type_id integer
---@field x number
---@field y number
---@field z number
---@field yaw number
---@field pitch number
---@field head_yaw number
---@field data integer
---@field custom_name_visible boolean
---@field custom_name string

---@class MCSInventoryInfo
---@field inventory_id integer
---@field used boolean
---@field is_item boolean
---@field is_block boolean
---@field is_food boolean
---@field item_id integer
---@field block_state_id integer
---@field count integer

---@class MCSCommandContext
---@field is_console boolean @ True for the local console and authenticated remote-command bridge.
---@field is_op boolean
---@field source "console"|"player"
---@field playername? string
---@field username? string @ Alias for playername.
---@field uuid? string
---@field entity_id? integer
---@field fd? integer

---@class MCSEvent
---@field type integer
---@field cancellable boolean
---@field cancelled boolean
---@field playername? string
---@field username? string
---@field entity_id? integer
---@field message? string
---@field x? number
---@field y? number
---@field z? number
---@field world_name? string Active save whose spawn was set.
---@field dimension_name? string Dimension identifier for the world spawn.
---@field block_x? integer Floored spawn X used by level.dat and the client packet.
---@field block_y? integer Floored spawn Y used by level.dat and the client packet.
---@field block_z? integer Floored spawn Z used by level.dat and the client packet.
---@field yaw? number
---@field pitch? number
---@field action? integer
---@field hand? integer
---@field direction? integer
---@field sequence? integer
---@field item_id? integer
---@field block_state_id? integer
---@field inventory_id? integer
---@field count? integer
---@field source? integer
---@field cursor_x? number
---@field cursor_y? number
---@field cursor_z? number
---@field inside_block? boolean
---@field world_border_hit? boolean
---@field target_entity_id? integer
---@field target_playername? string
---@field target_username? string
---@field attacker_entity_id? integer
---@field container_id? integer
---@field window_id? integer Alias for container_id.
---@field inventory_type? integer Open Screen menu type id recorded by the server.
---@field container_type? integer Alias for inventory_type.
---@field state_id? integer
---@field slot_id? integer
---@field button? integer For PICKUP, 0 is left click and 1 is right click.
---@field container_input? integer 0=PICKUP, 1=QUICK_MOVE, 2=SWAP, 3=CLONE, 4=THROW, 5=QUICK_CRAFT, 6=PICKUP_ALL.
---@field changed_slot_count? integer
---@field first_changed_slot_id? integer
---@field first_changed_item_id? integer
---@field first_changed_item_count? integer
---@field carried_item_id? integer
---@field carried_item_count? integer
---@field instance_name? string Created child instance name.
---@field template_name? string Source template for instances created with mcs_server_start_instance_from.
---@field port? integer Child instance listen port.

---@param message string
---@param log_type? integer @ Optional log level: MCS_LOG_DEBUG, MCS_LOG_INFO, MCS_LOG_WARN, or MCS_LOG_ERROR.
---@return boolean
function mcs_server_send_message(message, log_type) end

---Register a server command in the native command registry and client command tree.
---The registration is removed automatically when the Lua runtime unloads.
---@param command string @ One command token without a leading slash or whitespace.
---@param usage string @ Full usage text, beginning with command.
---@param description string|nil
---@param need_op boolean
---@param callback fun(context:MCSCommandContext, args:string[]):boolean|nil @ Return false to show usage; any other return value means success.
---@return boolean
function mcs_command_register(command, usage, description, need_op, callback) end

---Request a graceful server shutdown.
---@return boolean @ True when the shutdown request was accepted or was already pending.
function mcs_server_shutdown() end

---@return integer @ Current process listen port after command-line overrides.
function mcs_server_get_port() end

---@param start_port? integer @ First port to probe; defaults to 10000.
---@return integer|nil @ First TCP port that can currently be bound, or nil when none is available.
function mcs_server_find_available_port(start_port) end

---@param instance_name string @ Isolated directory name under instances/.
---@param port integer
---@return boolean @ True only after the child server is accepting connections.
function mcs_server_start_instance(instance_name, port) end

---@param path string
---@param timeout_ms? integer
---@return integer? lock_id
function mcs_server_file_lock(path, timeout_ms) end

---@param lock_id integer
---@return boolean
function mcs_server_file_unlock(lock_id) end

---Send a signed command to a dynamic target using the local identity and cluster secret.
---The shared secret remains inside the native runtime and is never returned to Lua.
---@param target_id string @ The target server-id configured by the receiver.
---@param address string @ Target IPv4 address.
---@param port integer @ Target Remote listener port.
---@param command string
---@return boolean success
---@return string|nil response @ "OK", "ERR", or nil on a transport/configuration failure.
function mcs_remote_command_send(target_id, address, port, command) end

---@param message string
---@param log_type? integer @ Optional log level: MCS_LOG_DEBUG, MCS_LOG_INFO, MCS_LOG_WARN, or MCS_LOG_ERROR.
---@return boolean
function mcs_chat_send_system_message(message, log_type) end

---@param playername string
---@param message string
---@return boolean
function mcs_chat_send_system_message_to_player(playername, message) end

---@param message string
---@return boolean
function mcs_chat_send_system_message_all_player(message) end

---@param playername string @ Viewer that receives the block update.
---@param x number
---@param y number
---@param z number
---@param block_name_or_state_id string|integer @ Block name such as stone/minecraft:stone, or a 26.1.2 block state id.
---@return boolean
function mcs_block_place(playername, x, y, z, block_name_or_state_id) end

---@param x integer
---@param y integer
---@param z integer
---@param block_name_or_state_id string|integer @ Block name such as stone/minecraft:stone, or a 26.1.2 block state id.
---Broadcast a single-block visual update to connected players without mutating server world state.
---@return boolean
function mcs_block_broadcast_update(x, y, z, block_name_or_state_id) end

---@param x integer
---@param y integer
---@param z integer
---@return integer
function mcs_block_get_state(x, y, z) end

---@param block_name string @ Accepts the optional minecraft: namespace; returns the default block state id.
---@return integer|nil
function mcs_block_state_id_from_name(block_name) end

---@param block_name_or_state_id string|integer
---@return boolean
function mcs_block_state_is_solid(block_name_or_state_id) end

---@param x integer
---@param y integer
---@param z integer
---@return boolean
function mcs_block_is_solid(x, y, z) end

---@param playername string @ Viewer that receives the crack animation.
---@param animation_id integer @ Stable id used to update/clear one crack overlay; a player entity id is a convenient choice.
---@param x integer
---@param y integer
---@param z integer
---@param stage integer @ 0..9 for crack progress, or -1 to clear.
---@return boolean
function mcs_block_set_break_animation(playername, animation_id, x, y, z, stage) end

---@param entity_type_id integer
---@param x number
---@param y number
---@param z number
---@param yaw? number
---@param pitch? number
---@param head_yaw? number
---@param data? integer
---@param name_component? string @ Plain text or JSON Text Component.
---@return integer|nil
function mcs_entity_spawn(entity_type_id, x, y, z, yaw, pitch, head_yaw, data, name_component) end

---Create a player-shaped entity with a persistent profile and skin.
---@param username string
---@param uuid string
---@param x number
---@param y number
---@param z number
---@param yaw number
---@param pitch number
---@param listed boolean
---@param texture_value string
---@param texture_signature? string
---@return integer|nil entity_id
function mcs_fake_player_add(username, uuid, x, y, z, yaw, pitch, listed, texture_value, texture_signature) end

---Set whether a fake player's original GameProfile name is rendered above it.
---@param playername string @ Viewer that receives the entity metadata.
---@param entity_id integer
---@param visible boolean
---@return boolean success
function mcs_fake_player_set_name_visible(entity_id, visible) end

---@param entity_type_id integer
---@param x number
---@param y number
---@param z number
---@param velocity_x number
---@param velocity_y number
---@param velocity_z number
---@param yaw? number
---@param pitch? number
---@param head_yaw? number
---@param data? integer
---@return integer|nil
function mcs_entity_spawn_with_velocity(entity_type_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, head_yaw, data) end

---@param entity_id integer
---@param x number
---@param y number
---@param z number
---@param yaw number
---@param pitch? number
---@param head_yaw? number
---@return boolean
function mcs_entity_rotate(entity_id, x, y, z, yaw, pitch, head_yaw) end

---@param entity_id integer
---@param x number
---@param y number
---@param z number
---@param velocity_x number
---@param velocity_y number
---@param velocity_z number
---@param yaw number
---@param pitch? number
---@param head_yaw? number
---@param on_ground? boolean
---@return boolean
function mcs_entity_move(entity_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, head_yaw, on_ground) end

---@param entity_id integer
---@return boolean
---Remove a generic runtime entity from connected clients and the entity manager.
---Player entities cannot be removed through this API.
function mcs_entity_remove(entity_id) end

---@param entity_id integer
---@param name string @ Plain text or JSON Text Component.
---@param visible boolean
---@return boolean
function mcs_entity_set_custom_name(entity_id, name, visible) end

---@param x number
---@param y number
---@param z number
---@param text string @ Plain text or JSON Text Component.
---@return integer|nil @ Runtime text-display entity id.
function mcs_hologram_create(x, y, z, text) end

---@param entity_id integer
---@param text string @ Plain text or JSON Text Component.
---@return boolean
function mcs_hologram_set_text(entity_id, text) end

---@param entity_id integer
---@param x number
---@param y number
---@param z number
---@return boolean
function mcs_hologram_move(entity_id, x, y, z) end

---@param entity_id integer
---@return boolean
function mcs_hologram_remove(entity_id) end

---@param rain_level number
---@param thunder_level number
---@param raining boolean
---Set overworld weather presentation for connected players.
---This Lua API intentionally only exposes the direct weather update call.
---Internal duration countdown and next-weather scheduling stay inside `play_world.c`.
---@return boolean
function mcs_world_update_weather(rain_level, thunder_level, raining) end

---@param time integer @ Non-negative Minecraft world time in ticks.
---Send one Set Time packet to each currently initialized player.
---The value is not stored, advanced, scheduled, or resent to later joins.
---@return boolean
function mcs_world_set_time(time) end

---@param dimension_name string
---@param x integer
---@param y integer
---@param z integer
---@param yaw? number
---@param pitch? number
---@return boolean
function mcs_world_set_default_spawn_position(dimension_name, x, y, z, yaw, pitch) end

---@return integer
function mcs_player_count() end

---@param playername string
---@return MCSPlayerInfo|nil
function mcs_player_get_info_by_name(playername) end

---@param uuid string
---@return MCSPlayerInfo|nil
function mcs_player_get_info_by_uuid(uuid) end

---@param fd integer
---@return MCSPlayerInfo|nil
function mcs_player_get_info_by_fd(fd) end

---@param identity string @ Minecraft username or canonical UUID.
---@return boolean
function mcs_whitelist_add(identity) end

---@param identity string @ Minecraft username or canonical UUID.
---@return boolean
function mcs_whitelist_remove(identity) end

---@param identity string @ Minecraft username or canonical UUID.
---@return boolean
function mcs_whitelist_contains(identity) end

---@param identity string @ Minecraft username or canonical UUID.
---@param uuid? string @ Optional UUID when identity is a username.
---@return boolean
function mcs_ban_add(identity, uuid) end

---@param identity string @ Minecraft username or canonical UUID.
---@return boolean
function mcs_ban_remove(identity) end

---@param identity string @ Minecraft username or canonical UUID.
---@return boolean
function mcs_ban_contains(identity) end

---@param ip string @ IPv4 address.
---@return boolean
function mcs_ban_ip_add(ip) end

---@param ip string @ IPv4 address.
---@return boolean
function mcs_ban_ip_remove(ip) end

---@param ip string @ IPv4 address.
---@return boolean
function mcs_ban_ip_contains(ip) end

---@param entity_id integer
---@return MCSEntityInfo|nil
function mcs_entity_get_info_by_id(entity_id) end

---@return MCSPlayerInfo[]
function mcs_player_list_info() end

---@param playername string
---@return boolean
function mcs_player_kick(playername) end

---@param playername string
---@param x number
---@param y number
---@param z number
---@param yaw? number
---@param pitch? number
---@return boolean
function mcs_player_tp_by_name(playername, x, y, z, yaw, pitch) end

---@param playername string
---@param x number
---@param y number
---@param z number
---@param velocity_x number
---@param velocity_y number
---@param velocity_z number
---@param yaw? number
---@param pitch? number
---@return boolean
function mcs_player_sync_position_with_velocity(playername, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch) end

---@param playername string
---@param host string
---@param port? integer
---@return boolean
function mcs_player_transfer(playername, host, port) end

---@param playername string
---@param channel string @ Namespaced Minecraft custom-payload channel.
---@param payload string @ Binary-safe raw payload bytes.
---@return boolean
function mcs_player_send_custom_payload(playername, channel, payload) end

---@param playername string
---@param gamemode MCSGamemode|"survival"|"creative"|"adventure"|"spectator"
---@return boolean
function mcs_player_set_gamemode(playername, gamemode) end

---@param playername string
---@param progress number @ Filled fraction of the experience bar, from 0.0 to 1.0.
---@param level integer @ Level number displayed above the bar; must be non-negative.
---@param total_experience integer @ Total experience value sent to the client; must be non-negative.
---@return boolean
function mcs_player_set_experience(playername, progress, level, total_experience) end

---@param playername string
---@param name string @ Plain Player Info/profile name; must fit the protocol username limit.
---@param visible boolean @ When false, only the runtime entity record is updated.
---@return boolean
function mcs_player_set_custom_name(playername, name, visible) end

---@param playername string
---@param name string @ Plain text or JSON Text Component used as a scoreboard-team prefix.
---@param visible boolean @ False removes the generated team from viewers.
---@return boolean
function mcs_player_set_custom_prefix_name(playername, name, visible) end

---@param playername string
---@param viewername? string @ When present, hide only from this viewer.
---@return boolean
function mcs_player_hide(playername, viewername) end

---@param playername string
---@param viewername? string @ When present, show only to this viewer.
---@return boolean
function mcs_player_show(playername, viewername) end

---@param playername string
---@param health number
---@param food integer
---@param food_saturation number
---@return boolean
function mcs_player_update_health(playername, health, food, food_saturation) end
---@param playername string
---@param armor number @ Vanilla armor attribute value from 0 to 30, rendered above the health bar.
---@return boolean
function mcs_player_set_armor_value(playername, armor) end

---@param entity_id integer
---@param hand integer @ 0=main hand, 1=offhand.
---@param item_id integer
---@param count? integer @ Defaults to 1; use 0 or air to clear the visual item.
---@param nbt_data? string @ Optional custom-name component input.
---@return boolean
---Stores the visual equipment in the entity manager; it does not mutate a connected player's inventory.
function mcs_player_set_held_item_display(entity_id, hand, item_id, count, nbt_data) end

---@param viewer_name string @ Viewer that receives the equipment packet.
---@param entity_id integer
---@param equipment_slot integer @ 0=main hand, 1=offhand, 2=boots, 3=leggings, 4=chestplate, 5=helmet, 6=body.
---@param item_id integer
---@param count? integer @ Defaults to 1; use 0 or air to clear the visual equipment.
---@param nbt_data? string @ Optional custom-name component input.
---@return boolean
---Broadcasts and persists one visual equipment slot without mutating the real inventory.
function mcs_player_set_equipment_display(viewer_name, entity_id, equipment_slot, item_id, count, nbt_data) end

---@param entity_id integer
---@param equipment_slot integer
---@param item_id integer
---@param count? integer
---@param nbt_data? string
---@return boolean
---Broadcasts visual equipment to every current viewer, including the entity owner.
function mcs_player_set_equipment_display_for_all(entity_id, equipment_slot, item_id, count, nbt_data) end

---@param entity_id integer
---@param equipment_slot integer
---@param item_id integer
---@param count? integer
---@param nbt_data? string
---@return boolean
---Updates visual equipment for every viewer except the real player who owns entity_id.
function mcs_player_set_equipment_display_for_others(entity_id, equipment_slot, item_id, count, nbt_data) end

---@param entity_id integer
---@param pulling boolean @ True starts the active-use pose; false stops it.
---@param hand? integer @ 0=main hand, 1=offhand; defaults to main hand.
---@return boolean
function mcs_player_set_bow_animation(playername, entity_id, pulling, hand) end

---@param playername string
---@param hand? integer @ 0=main hand, 1=offhand; defaults to main hand.
---@return boolean
---Broadcasts the arm swing used for block placement and block breaking.
function mcs_player_swing_hand(playername, hand) end

---@param playername string
---@param effect_id integer|string @ Effect ID, effect constant, or effect name.
---@param amplifier integer
---@param duration integer|string @ Seconds, or "infinite"
---@param flags? string
---@return boolean
function mcs_player_set_effect(playername, effect_id, amplifier, duration, flags) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@param item_id integer
---@param count integer
---@param nbt_data? string @ Plain text, `{CustomName:'text'}`, or direct JSON Text Component; custom-name only.
---@return boolean
function mcs_player_set_inventory_item(playername, inventory_id, item_id, count, nbt_data) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@param item_id integer
---@param count integer
---@param nbt_data? string @ Plain text, `{CustomName:'text'}`, or direct JSON Text Component; custom-name only.
---@return boolean
function mcs_player_give_item(playername, inventory_id, item_id, count, nbt_data) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@return MCSInventoryInfo|nil
function mcs_player_get_inventory_info(playername, inventory_id) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@return boolean
function mcs_player_inventory_is_item(playername, inventory_id) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@return boolean
function mcs_player_inventory_is_block(playername, inventory_id) end

---@param playername string
---@param inventory_id integer Player inventory slot `0..35`; selected hotbar slots are `0..8`.
---@return boolean
function mcs_player_inventory_is_food(playername, inventory_id) end

---@param playername string
---@param pages? string|string[] @ One page string or an array containing 1 to 100 page strings.
---Force-open the book GUI with optional page text, then restore the original main-hand slot.
---@return boolean
function mcs_player_open_book(playername, pages) end

---@param playername string
---@param pages string|string[] @ Plain-text pages; defaults title and author to `OakMC`.
---@return boolean
function mcs_player_open_written_book(playername, pages) end

---@param playername string
---@param title string @ Written-book title, up to 32 UTF-8 characters.
---@param pages string|string[] @ Plain-text pages.
---@return boolean
function mcs_player_open_book_with_title(playername, title, pages) end

---@param playername string
---@param author string @ Written-book author, up to 16 UTF-8 characters.
---@param pages string|string[] @ Plain-text pages.
---@return boolean
function mcs_player_open_book_with_author(playername, author, pages) end

---@param playername string
---@param title string @ Written-book title, up to 32 UTF-8 characters.
---@param author string @ Written-book author, up to 16 UTF-8 characters.
---@param page_components string|string[] @ Plain text or JSON Text Components.
---@return boolean
function mcs_player_open_book_components(playername, title, author, page_components) end

---@param playername string
---@param window_id integer
---@param inventory_type integer
---@param title string @ Plain text or JSON Text Component.
---Open a client GUI screen/window. `inventory_type` is the protocol menu type registry id for this Minecraft version.
---@return boolean
function mcs_player_open_screen(playername, window_id, inventory_type, title) end

---@param playername string
---@param container_id integer
---@param state_id integer
---@param slot_id integer
---@param item_id integer
---@param count integer
---@param nbt_data? string @ Plain text, `{CustomName:'text'}`, or direct JSON Text Component; custom-name only.
---Update one slot in an opened GUI screen/container. This does not mutate the player's tracked inventory.
---@return boolean
function mcs_player_set_screen_slot(playername, container_id, state_id, slot_id, item_id, count, nbt_data) end

---@param playername string
---@param uuid string
---@param title string @ Plain text or JSON Text Component.
---@param health? number @ 0.0 to 1.0
---@param color? MCSBossBarColor
---@param dividers? MCSBossBarDivision
---@param flags? integer
---@return boolean
function mcs_player_boss_bar_add(playername, uuid, title, health, color, dividers, flags) end

---@param playername string
---@param uuid string
---@return boolean
function mcs_player_boss_bar_remove(playername, uuid) end

---@param playername string
---@param uuid string
---@param health number @ 0.0 to 1.0
---@return boolean
function mcs_player_boss_bar_update_health(playername, uuid, health) end

---@param playername string
---@param uuid string
---@param color MCSBossBarColor
---@param dividers MCSBossBarDivision
---@return boolean
function mcs_player_boss_bar_update_style(playername, uuid, color, dividers) end

---@param playername string
---@param uuid string
---@param flags integer
---@return boolean
function mcs_player_boss_bar_update_flags(playername, uuid, flags) end

---@param playername string
---@param sound_id string
---@param sound_category integer
---@param volume? number
---@param pitch? number
---@param seed? integer
---@return boolean
function mcs_player_play_sound(playername, sound_id, sound_category, volume, pitch, seed) end

---@param playername string
---@param sound_name string
---@param sound_category integer
---@param volume? number
---@param pitch? number
---@param seed? integer
---@return boolean
function mcs_player_play_sound_name(playername, sound_name, sound_category, volume, pitch, seed) end

---@param playername string
---@param allow_flying boolean @ Grants or revokes flight without changing the player's gamemode.
---@return boolean
function mcs_player_set_allow_flying(playername, allow_flying) end

---@param playername string
---@param flying_speed number
---@return boolean
function mcs_player_set_flying_speed(playername, flying_speed) end

---@param playername string
---@param reset_times? boolean
---@return boolean
function clear_title(playername, reset_times) end

---@param playername string
---@param text string @ Plain text or JSON Text Component.
---@return boolean
function set_subtitle_text(playername, text) end

---@param playername string
---@param fade_in integer
---@param stay integer
---@param fade_out integer
---@return boolean
function set_time(playername, fade_in, stay, fade_out) end

---@param playername string
---@param text string @ Plain text or JSON Text Component.
---@return boolean
function set_title_text(playername, text) end

---@param playername string
---@param reset_times? boolean
---@return boolean
function mcs_title_clear(playername, reset_times) end

---@param playername string
---@param text string @ Plain text or JSON Text Component; use an empty string to clear it.
---@return boolean
function mcs_title_set_action_bar_text(playername, text) end

---@param playername string
---@param text string @ Plain text or JSON Text Component.
---@return boolean
function mcs_title_set_subtitle_text(playername, text) end

---@param playername string
---@param fade_in integer
---@param stay integer
---@param fade_out integer
---@return boolean
function mcs_title_set_time(playername, fade_in, stay, fade_out) end

---@param playername string
---@param text string @ Plain text or JSON Text Component.
---@return boolean
function mcs_title_set_text(playername, text) end

---@param playername string
---@param objective_name string @ Internal objective name, 1-16 bytes.
---@param title string @ Plain text or JSON Text Component.
---@return boolean
function mcs_scoreboard_sidebar_show(playername, objective_name, title) end

---@param playername string
---@param objective_name string
---@param title string @ Plain text or JSON Text Component.
---@return boolean
function mcs_scoreboard_sidebar_update_title(playername, objective_name, title) end

---@param playername string
---@param objective_name string
---@param entry_name string @ Stable internal entry key.
---@param value integer
---@param display_name? string @ Optional plain text or JSON Text Component shown instead of entry_name.
---@param hide_value? boolean @ Hide the rendered numeric score while retaining value for ordering. Defaults to true.
---@return boolean
function mcs_scoreboard_sidebar_set_score(playername, objective_name, entry_name, value, display_name, hide_value) end

---@param playername string
---@param objective_name string
---@param entry_name string
---@return boolean
function mcs_scoreboard_sidebar_remove_score(playername, objective_name, entry_name) end

---@param playername string
---@param objective_name string
---@return boolean
function mcs_scoreboard_sidebar_hide(playername, objective_name) end

---@param playername string
---@param particle_name_or_id string|integer @ Protocol 775 particle registry name/id; data-bearing particles are rejected.
---@param x number
---@param y number
---@param z number
---@param offset_x? number
---@param offset_y? number
---@param offset_z? number
---@param speed? number
---@param count? integer
---@param force_spawn? boolean
---@param important? boolean
---@return boolean
function mcs_particle_spawn(playername, particle_name_or_id, x, y, z, offset_x, offset_y, offset_z, speed, count, force_spawn, important) end

---@param playername string
---@return MCSGamemode|nil
function mcs_player_get_gamemode(playername) end

---@param target string
---@param source_entity_id integer
---@param damage_cause integer
---@param amount number
---@return boolean
function mcs_player_apply_damage(target, source_entity_id, amount, damage_cause) end

---@param event_type integer
---@param priority integer
---@param callback fun(event:MCSEvent)
---@param options? {cancellable:boolean?, cancelled:boolean?} Defaults to cancellable=true, cancelled=false.
---@return boolean
function mcs_event_register(event_type, priority, callback, options) end

MCS_EVENT_PLAYER_CHAT = 0
MCS_EVENT_SYSTEM_CHAT = 1
MCS_EVENT_PLAYER_JOIN = 2
MCS_EVENT_PLAYER_QUIT = 3
MCS_EVENT_PLAYER_MOVE = 4
MCS_EVENT_BLOCK_PLACE = 5
MCS_EVENT_BLOCK_BREAK = 6
MCS_EVENT_CREATIVE_SLOT_UPDATE = 7
MCS_EVENT_SERVER_START = 8
MCS_EVENT_SERVER_TICK = 9
MCS_EVENT_ENTITY_ATTACK = 10
MCS_EVENT_ENTITY_INTERACT = 11
MCS_EVENT_USE_ITEM = 12
MCS_EVENT_USE_FOOD = 13
MCS_EVENT_SCREEN_CLICK = 14
MCS_EVENT_PLAYER_RECEIVE_ITEM = 15
MCS_EVENT_RELEASE_USE_ITEM = 16
MCS_EVENT_PLAYER_INITIALIZED = 17
MCS_EVENT_HELD_ITEM_CHANGE = 18
MCS_EVENT_SERVER_INSTANCE_CREATED = 19
MCS_EVENT_WORLD_SPAWN_SET = 20

MCS_ITEM_RECEIVE_SOURCE_COMMAND = 0
MCS_ITEM_RECEIVE_SOURCE_API = 1
MCS_ITEM_RECEIVE_SOURCE_PICKUP = 2
MCS_ITEM_RECEIVE_SOURCE_REWARD = 3
MCS_ITEM_RECEIVE_SOURCE_CONTAINER = 4

MCS_LOG_DEBUG = 1
MCS_LOG_INFO = 2
MCS_LOG_WARN = 3
MCS_LOG_ERROR = 4

MCS_GAMEMODE_SURVIVAL = 0
MCS_GAMEMODE_CREATIVE = 1
MCS_GAMEMODE_ADVENTURE = 2
MCS_GAMEMODE_SPECTATOR = 3

MCS_EFFECT_INFINITE_DURATION = -1
MCS_EFFECT_SPEED = 0
MCS_EFFECT_SLOWNESS = 1
MCS_EFFECT_HASTE = 2
MCS_EFFECT_MINING_FATIGUE = 3
MCS_EFFECT_STRENGTH = 4
MCS_EFFECT_INSTANT_HEALTH = 5
MCS_EFFECT_INSTANT_DAMAGE = 6
MCS_EFFECT_JUMP_BOOST = 7
MCS_EFFECT_NAUSEA = 8
MCS_EFFECT_REGENERATION = 9
MCS_EFFECT_RESISTANCE = 10
MCS_EFFECT_FIRE_RESISTANCE = 11
MCS_EFFECT_WATER_BREATHING = 12
MCS_EFFECT_INVISIBILITY = 13
MCS_EFFECT_BLINDNESS = 14
MCS_EFFECT_NIGHT_VISION = 15
MCS_EFFECT_HUNGER = 16
MCS_EFFECT_WEAKNESS = 17
MCS_EFFECT_POISON = 18
MCS_EFFECT_WITHER = 19
MCS_EFFECT_HEALTH_BOOST = 20
MCS_EFFECT_ABSORPTION = 21
MCS_EFFECT_SATURATION = 22
MCS_EFFECT_GLOWING = 23
MCS_EFFECT_LEVITATION = 24
MCS_EFFECT_LUCK = 25
MCS_EFFECT_UNLUCK = 26
MCS_EFFECT_SLOW_FALLING = 27
MCS_EFFECT_CONDUIT_POWER = 28
MCS_EFFECT_DOLPHINS_GRACE = 29
MCS_EFFECT_BAD_OMEN = 30
MCS_EFFECT_HERO_OF_THE_VILLAGE = 31
MCS_EFFECT_DARKNESS = 32
MCS_EFFECT_TRIAL_OMEN = 33
MCS_EFFECT_RAID_OMEN = 34
MCS_EFFECT_WIND_CHARGED = 35
MCS_EFFECT_WEAVING = 36
MCS_EFFECT_OOZING = 37
MCS_EFFECT_INFESTED = 38
MCS_EFFECT_BREATH_OF_THE_NAUTILUS = 39

MCS_BOSS_BAR_ACTION_ADD = 0
MCS_BOSS_BAR_ACTION_REMOVE = 1
MCS_BOSS_BAR_ACTION_UPDATE_HEALTH = 2
MCS_BOSS_BAR_ACTION_UPDATE_TITLE = 3
MCS_BOSS_BAR_ACTION_UPDATE_STYLE = 4
MCS_BOSS_BAR_ACTION_UPDATE_FLAGS = 5

MCS_BOSS_BAR_COLOR_PINK = 0
MCS_BOSS_BAR_COLOR_BLUE = 1
MCS_BOSS_BAR_COLOR_RED = 2
MCS_BOSS_BAR_COLOR_GREEN = 3
MCS_BOSS_BAR_COLOR_YELLOW = 4
MCS_BOSS_BAR_COLOR_PURPLE = 5
MCS_BOSS_BAR_COLOR_WHITE = 6

MCS_BOSS_BAR_DIVISION_NONE = 0
MCS_BOSS_BAR_DIVISION_6 = 1
MCS_BOSS_BAR_DIVISION_10 = 2
MCS_BOSS_BAR_DIVISION_12 = 3
MCS_BOSS_BAR_DIVISION_20 = 4

MCS_BOSS_BAR_FLAG_DARKEN_SKY = 1
MCS_BOSS_BAR_FLAG_DRAGON_MUSIC = 2
MCS_BOSS_BAR_FLAG_CREATE_FOG = 4

-- Audience-explicit client-visible APIs. The old playername forms remain
-- targeted compatibility APIs; *_for_others excludes owner_entity_id and
-- *_for_all includes every initialized client.
function mcs_player_hurt_animation(playername, yaw) end
function mcs_player_hurt_animation_for_others(owner_entity_id, yaw) end
function mcs_player_hurt_animation_for_all(entity_id, yaw) end
function mcs_player_set_bow_animation_for_others(entity_id, pulling, hand) end
function mcs_player_set_bow_animation_for_all(entity_id, pulling, hand) end
function mcs_player_swing_hand_for_others(entity_id, hand) end
function mcs_player_swing_hand_for_all(entity_id, hand) end
function mcs_particle_spawn_for_others(owner_entity_id, particle_name_or_id, x, y, z, offset_x, offset_y, offset_z, speed, count, force_spawn, important) end
function mcs_particle_spawn_for_all(particle_name_or_id, x, y, z, offset_x, offset_y, offset_z, speed, count, force_spawn, important) end
function mcs_title_clear_for_others(owner_entity_id, reset_times) end
function mcs_title_clear_for_all(reset_times) end
function mcs_title_set_action_bar_text_for_others(owner_entity_id, text) end
function mcs_title_set_action_bar_text_for_all(text) end
function mcs_title_set_subtitle_text_for_others(owner_entity_id, text) end
function mcs_title_set_subtitle_text_for_all(text) end
function mcs_title_set_time_for_others(owner_entity_id, fade_in, stay, fade_out) end
function mcs_title_set_time_for_all(fade_in, stay, fade_out) end
function mcs_title_set_text_for_others(owner_entity_id, text) end
function mcs_title_set_text_for_all(text) end
function mcs_player_play_sound_for_others(owner_entity_id, sound_id, sound_category, volume, pitch, seed) end
function mcs_player_play_sound_for_all(sound_id, sound_category, volume, pitch, seed) end
function mcs_player_play_sound_name_for_others(owner_entity_id, sound_name, sound_category, volume, pitch, seed) end
function mcs_player_play_sound_name_for_all(sound_name, sound_category, volume, pitch, seed) end
function mcs_chat_send_system_message_for_others(owner_entity_id, message) end
function mcs_chat_send_system_message_for_all(message) end
function mcs_scoreboard_sidebar_show_for_others(owner_entity_id, objective_name, title) end
function mcs_scoreboard_sidebar_show_for_all(objective_name, title) end
function mcs_scoreboard_sidebar_update_title_for_others(owner_entity_id, objective_name, title) end
function mcs_scoreboard_sidebar_update_title_for_all(objective_name, title) end
function mcs_scoreboard_sidebar_set_score_for_others(owner_entity_id, objective_name, entry_name, value, display_name, hide_value) end
function mcs_scoreboard_sidebar_set_score_for_all(objective_name, entry_name, value, display_name, hide_value) end
function mcs_scoreboard_sidebar_remove_score_for_others(owner_entity_id, objective_name, entry_name) end
function mcs_scoreboard_sidebar_remove_score_for_all(objective_name, entry_name) end
function mcs_scoreboard_sidebar_hide_for_others(owner_entity_id, objective_name) end
function mcs_scoreboard_sidebar_hide_for_all(objective_name) end
function mcs_player_boss_bar_add_for_others(owner_entity_id, uuid, title, health, color, dividers, flags) end
function mcs_player_boss_bar_add_for_all(uuid, title, health, color, dividers, flags) end
function mcs_player_boss_bar_remove_for_others(owner_entity_id, uuid) end
function mcs_player_boss_bar_remove_for_all(uuid) end
function mcs_player_boss_bar_update_health_for_others(owner_entity_id, uuid, health) end
function mcs_player_boss_bar_update_health_for_all(uuid, health) end
function mcs_player_boss_bar_update_style_for_others(owner_entity_id, uuid, color, dividers) end
function mcs_player_boss_bar_update_style_for_all(uuid, color, dividers) end
function mcs_player_boss_bar_update_flags_for_others(owner_entity_id, uuid, flags) end
function mcs_player_boss_bar_update_flags_for_all(uuid, flags) end
