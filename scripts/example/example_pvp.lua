-- Last-player-standing PvP room. Two players start a 15-second countdown;
-- reaching the four-player room capacity starts the match immediately.
--
-- Players are assigned one arena pad while the room fills. When the countdown
-- expires or the room fills, everybody is reset to a pad and combat starts.
-- Eliminated players remain in Adventure mode, gain flight, are hidden from
-- active players, and receive a bed that returns them to the lobby. The winner
-- receives a persistent economy reward when the economy plugin is available,
-- then the room sends everybody back after five seconds.

local proxy_transfer = assert(dofile("plugins/proxy_transfer.lua"))
local waiting_room = require("plugins.common.waiting_room")

local TICKS_PER_SECOND = 20
local RETURN_DELAY_TICKS = 5 * TICKS_PER_SECOND
local WAIT_TIMEOUT_TICKS = 15 * TICKS_PER_SECOND
local MIN_PLAYERS = 2
local MAX_PLAYERS = 4
local ATTACK_DAMAGE = 1
local SWORD_ATTACK_DAMAGE = 7
local BASE_ATTACK_SPEED = 4.0
local SWORD_ATTACK_SPEED = 1.6
local ATTACK_STRENGTH_PARTIAL_TICK = 0.5
local FULL_ATTACK_THRESHOLD = 0.9
local CRITICAL_DAMAGE_MULTIPLIER = 1.5
local HURT_RESISTANCE_TICKS = 10
local MELEE_REACH = 3.0
local DIAMOND_ARMOR_POINTS = 20
local DIAMOND_ARMOR_TOUGHNESS = 8
local SATURATED_REGEN_INTERVAL_TICKS = 10
local HUNGRY_REGEN_INTERVAL_TICKS = 80
local NATURAL_REGEN_MIN_FOOD = 18
local SATURATED_REGEN_MAX_EXHAUSTION = 6.0
local HUNGRY_REGEN_AMOUNT = 1.0
local HUNGRY_REGEN_EXHAUSTION = 6.0
local FOOD_EXHAUSTION_THRESHOLD = 4.0
local SPRINT_EXHAUSTION_PER_BLOCK = 0.1
local WALK_JUMP_EXHAUSTION = 0.05
local SPRINT_JUMP_EXHAUSTION = 0.2
local ATTACK_EXHAUSTION = 0.1
local DEFAULT_FOOD_SATURATION = 5.0
local WINNER_REWARD_COINS = 100
local ELIMINATION_Y = -63
local ARMOR_SYNC_TICKS = TICKS_PER_SECOND
local HEAL_AMOUNT = 4
local MAIN_HAND = 0
local ARROW_ENTITY_TYPE = 6
local SNOWBALL_ENTITY_TYPE = 120
local MIN_BOW_CHARGE_TICKS = 3
local FULL_BOW_CHARGE_TICKS = 20
local MAX_PROJECTILE_TICKS = 200
local MAX_EMBEDDED_TICKS = 1200
local MAX_ACTIVE_PROJECTILES = 256
local PROJECTILE_GRAVITY = 0.05
local PROJECTILE_AIR_DRAG = 0.99
local SNOWBALL_GRAVITY = 0.03
local SNOWBALL_SPEED = 1.5
local SNOWBALL_KNOCKBACK_HORIZONTAL = 0.8
local SNOWBALL_COUNT = 8
local SPEED_EFFECT_AMPLIFIER = 1
local SPEED_EFFECT_SECONDS = 30
local PROJECTILE_COLLISION_STEP = 0.2
local SHOOTER_GRACE_TICKS = 5
local PLAYER_HITBOX_RADIUS = 0.3
local PLAYER_HITBOX_HEIGHT = 1.8
local PLAYER_EYE_HEIGHT = 1.62

local LOBBY_SERVER_NAME = os.getenv("OAKMC_LOBBY_SERVER_NAME") or "lobby"
local LOBBY_HOST = os.getenv("OAKMC_LOBBY_HOST") or "127.0.0.1"
local LOBBY_PORT = tonumber(os.getenv("OAKMC_LOBBY_PORT") or "") or 10000

-- Protocol 775 / Minecraft 26.1 item registry IDs.
local ITEM_AIR = 0
local ITEM_WHITE_WOOL = 213
local ITEM_BOW = 895
local ITEM_ARROW = 896
local ITEM_DIAMOND_SWORD = 937
local ITEM_SNOWBALL = 1017
local ITEM_DIAMOND_HELMET = 971
local ITEM_DIAMOND_CHESTPLATE = 972
local ITEM_DIAMOND_LEGGINGS = 973
local ITEM_DIAMOND_BOOTS = 974
local ITEM_RED_BED = 1101
local ITEM_NETHER_STAR = 1241
local ITEM_POTION = 1291
local ITEM_SPLASH_POTION = 1292
local SWORD_SLOT = 0
local BOW_SLOT = 1
local HEALING_POTION_SLOTS = { 2, 3 }
local ARROW_SLOT = 4
local RETURN_BED_SLOT = 8
local WOOL_SLOT = 5
local SNOWBALL_SLOT = 6
local SPEED_POTION_SLOT = 7
local WINNER_TROPHY_SLOT = 7
local INVENTORY_SLOT_COUNT = 36
local EQUIPMENT_BOOTS = 2
local EQUIPMENT_LEGGINGS = 3
local EQUIPMENT_CHESTPLATE = 4
local EQUIPMENT_HELMET = 5
local WHITE_WOOL_BLOCK_STATE = 2293
local BLACK_WOOL_BLOCK_STATE = 2308

local ARENA_CENTER = { x = -111.5, y = -55, z = -8.5, yaw = 0, pitch = 0 }
local PLAYER_PADS = {
    { x = -86.5,  y = -55, z = -8.5,  yaw = 90,  pitch = 0 },
    { x = -136.5, y = -55, z = -8.5,  yaw = -90, pitch = 0 },
    { x = -111.5, y = -55, z = 16.5,  yaw = 180, pitch = 0 },
    -- The supplied fourth coordinate duplicated pad 3. This symmetric north
    -- pad prevents two players spawning inside each other.
    { x = -111.5, y = -55, z = -33.5, yaw = 0,   pitch = 0 },
}
local STATE_WAITING = "waiting"
local STATE_FIGHTING = "fighting"
local STATE_FINISHED = "finished"

local state = STATE_WAITING
local participants = {}
local participant_by_name = {}
local finish_ticks = 0
local returned_to_lobby = {}
local observer_names = {}
local tick_count = 0
local bow_charging = {}
local projectiles = {}
local held_item_display = {}
local waiting_countdown
local return_bed

local KNOCKBACK_HORIZONTAL = 0.4
local KNOCKBACK_SPRINT_BONUS = 0.5
local KNOCKBACK_VERTICAL = 0.4
local KNOCKBACK_MIN_DISTANCE = 0.001
local KNOCKBACK_MOTION_DAMPING = 0.5
local SPRINT_SPEED_THRESHOLD = 0.24
local SPRINT_FORWARD_DOT_THRESHOLD = 0.7
local MOTION_EPSILON = 0.0001

local function json_escape(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
end

local function component(text, color, bold)
    return string.format(
        '{"text":"%s","color":"%s","bold":%s,"italic":false}',
        json_escape(text),
        color or "white",
        bold and "true" or "false"
    )
end

local function player_name(event)
    return event and (event.playername or event.username) or nil
end

local function tell(playername, text, color, bold)
    mcs_chat_send_system_message_to_player(
        playername,
        component(text, color or "white", bold == true)
    )
end

local function broadcast(text, color, bold)
    mcs_chat_send_system_message_all_player(
        component(text, color or "white", bold == true)
    )
end

local function clear_inventory(playername)
    for slot = 0, INVENTORY_SLOT_COUNT - 1 do
        mcs_player_set_inventory_item(playername, slot, ITEM_AIR, 0, nil)
    end
end

local function teleport_to_pad(entry)
    local pad = PLAYER_PADS[entry.slot]
    if pad == nil then
        return false
    end
    return mcs_player_tp_by_name(
        entry.name,
        pad.x,
        pad.y,
        pad.z,
        pad.yaw,
        pad.pitch
    )
end

local function give_return_bed(playername)
    mcs_player_set_inventory_item(
        playername,
        RETURN_BED_SLOT,
        ITEM_RED_BED,
        1,
        component("右键返回大厅", "red", true)
    )
end

local function give_combat_loadout(playername)
    mcs_player_set_inventory_item(
        playername,
        SWORD_SLOT,
        ITEM_DIAMOND_SWORD,
        1,
        component("PVP 钻石剑", "aqua", true)
    )
    mcs_player_set_inventory_item(
        playername,
        BOW_SLOT,
        ITEM_BOW,
        1,
        component("PVP 战弓", "gold", true)
    )
    for _, slot in ipairs(HEALING_POTION_SLOTS) do
        mcs_player_set_inventory_item(
            playername,
            slot,
            ITEM_SPLASH_POTION,
            1,
            component("治疗药水", "light_purple", true)
        )
    end
    mcs_player_set_inventory_item(
        playername,
        ARROW_SLOT,
        ITEM_ARROW,
        5,
        component("PVP 箭矢", "yellow", true)
    )
    mcs_player_set_inventory_item(
        playername,
        WOOL_SLOT,
        ITEM_WHITE_WOOL,
        30,
        component("PVP 羊毛", "white", true)
    )
    mcs_player_set_inventory_item(
        playername,
        SNOWBALL_SLOT,
        ITEM_SNOWBALL,
        SNOWBALL_COUNT,
        component("击退雪球", "aqua", true)
    )
    mcs_player_set_inventory_item(
        playername,
        SPEED_POTION_SLOT,
        ITEM_POTION,
        1,
        component("疾速药水", "blue", true)
    )
end

local function equip_diamond_armor(playername)
    local player = mcs_player_get_info_by_name(playername)
    if player == nil then
        return false
    end
    local displayed = mcs_player_set_equipment_display_for_all(
        player.entity_id,
        EQUIPMENT_BOOTS,
        ITEM_DIAMOND_BOOTS,
        1,
        nil
    ) and mcs_player_set_equipment_display_for_all(
        player.entity_id,
        EQUIPMENT_LEGGINGS,
        ITEM_DIAMOND_LEGGINGS,
        1,
        nil
    ) and mcs_player_set_equipment_display_for_all(
        player.entity_id,
        EQUIPMENT_CHESTPLATE,
        ITEM_DIAMOND_CHESTPLATE,
        1,
        nil
    ) and mcs_player_set_equipment_display_for_all(
        player.entity_id,
        EQUIPMENT_HELMET,
        ITEM_DIAMOND_HELMET,
        1,
        nil
    )
    return displayed and mcs_player_set_armor_value(playername, DIAMOND_ARMOR_POINTS)
end

local function sync_held_item(playername)
    local player = mcs_player_get_info_by_name(playername)
    if player == nil then
        return false
    end
    local held = mcs_player_get_inventory_info(playername, player.selected_inventory_id)
    local item_id = ITEM_AIR
    local count = 0
    local nbt_data = nil
    if held ~= nil and held.used and held.count > 0 then
        item_id = held.item_id
        count = held.count
        nbt_data = held.nbt_data
    end
    local previous = held_item_display[playername]
    if previous ~= nil and previous.selected_inventory_id == player.selected_inventory_id and
        previous.item_id == item_id and previous.count == count then
        return true
    end
    local updated = mcs_player_set_equipment_display_for_others(
        player.entity_id,
        MAIN_HAND,
        item_id,
        count,
        nbt_data
    )
    if updated then
        held_item_display[playername] = {
            selected_inventory_id = player.selected_inventory_id,
            item_id = item_id,
            count = count,
        }
    end
    return updated
end

local function damage_after_diamond_armor(raw_damage)
    local toughness_factor = 2.0 + DIAMOND_ARMOR_TOUGHNESS / 4.0
    local effective_armor = math.min(
        20.0,
        math.max(
            DIAMOND_ARMOR_POINTS / 5.0,
            DIAMOND_ARMOR_POINTS - raw_damage / toughness_factor
        )
    )
    return raw_damage * (1.0 - effective_armor / 25.0)
end

local function attack_cooldown_ticks(held)
    local attack_speed = held ~= nil and held.used and held.item_id == ITEM_DIAMOND_SWORD
        and SWORD_ATTACK_SPEED or BASE_ATTACK_SPEED
    return TICKS_PER_SECOND / attack_speed
end

local function attack_strength(entry, held)
    local elapsed = tick_count - (entry.last_attack_tick or 0)
    return math.max(0.0, math.min(
        1.0,
        (elapsed + ATTACK_STRENGTH_PARTIAL_TICK) / attack_cooldown_ticks(held)
    ))
end

local function initialize_combat_state(entry, info)
    entry.last_attack_tick = tick_count - attack_cooldown_ticks({
        used = true,
        item_id = ITEM_DIAMOND_SWORD,
    })
    entry.last_hurt_tick = tick_count - HURT_RESISTANCE_TICKS
    entry.regen_tick = 0
    entry.food_exhaustion = 0.0
    entry.sprint_attack_consumed = false
    entry.motion = info ~= nil and {
        x = info.x,
        y = info.y,
        z = info.z,
        vx = 0.0,
        vy = 0.0,
        vz = 0.0,
        horizontal_speed = 0.0,
        sprinting = false,
    } or nil
end

local function update_player_motion(entry)
    local info = entry.connected and mcs_player_get_info_by_name(entry.name) or nil
    if info == nil then
        return
    end

    local previous = entry.motion
    local vx = previous ~= nil and info.x - previous.x or 0.0
    local vy = previous ~= nil and info.y - previous.y or 0.0
    local vz = previous ~= nil and info.z - previous.z or 0.0
    local horizontal_speed = math.sqrt(vx * vx + vz * vz)
    local yaw_radians = math.rad(info.yaw)
    local forward_x = -math.sin(yaw_radians)
    local forward_z = math.cos(yaw_radians)
    local forward_dot = 0.0
    if horizontal_speed > MOTION_EPSILON then
        forward_dot = (vx * forward_x + vz * forward_z) / horizontal_speed
    end
    local sprinting = horizontal_speed >= SPRINT_SPEED_THRESHOLD and
        forward_dot >= SPRINT_FORWARD_DOT_THRESHOLD

    if not sprinting then
        entry.sprint_attack_consumed = false
    end
    entry.motion = {
        x = info.x,
        y = info.y,
        z = info.z,
        vx = vx,
        vy = vy,
        vz = vz,
        horizontal_speed = horizontal_speed,
        sprinting = sprinting,
    }
end

local function broadcast_bow_animation(entity_id, pulling, hand)
    if entity_id == nil then
        return
    end
    for _, viewer in ipairs(mcs_player_list_info() or {}) do
        if viewer.username ~= nil and viewer.play_initialized then
            mcs_player_set_bow_animation(
                viewer.username,
                entity_id,
                pulling,
                hand or MAIN_HAND
            )
        end
    end
end

local function stop_bow_charge(name)
    local charge = bow_charging[name]
    if charge == nil then
        return nil
    end
    bow_charging[name] = nil
    broadcast_bow_animation(charge.entity_id, false, charge.hand)
    return charge
end

local function stop_all_bow_charges()
    local names = {}
    for name in pairs(bow_charging) do
        names[#names + 1] = name
    end
    for _, name in ipairs(names) do
        stop_bow_charge(name)
    end
end

local function bow_charge_power(charged_ticks)
    local elapsed = charged_ticks / FULL_BOW_CHARGE_TICKS
    local power = (elapsed * elapsed + 2.0 * elapsed) / 3.0
    return math.max(0.0, math.min(1.0, power))
end

local function direction_from_rotation(yaw, pitch)
    local yaw_radians = math.rad(yaw)
    local pitch_radians = math.rad(pitch)
    local pitch_cos = math.cos(pitch_radians)
    return -math.sin(yaw_radians) * pitch_cos,
        -math.sin(pitch_radians),
        math.cos(yaw_radians) * pitch_cos
end

local function projectile_rotation(vx, vy, vz)
    local horizontal = math.sqrt(vx * vx + vz * vz)
    return math.deg(math.atan(vx, vz)), math.deg(math.atan(vy, horizontal))
end

local function projectile_hurt_yaw(target, projectile)
    return math.deg(math.atan(-projectile.vz, -projectile.vx)) - target.yaw
end

local function find_arrow(player)
    for slot = 0, INVENTORY_SLOT_COUNT - 1 do
        local item = mcs_player_get_inventory_info(player.username, slot)
        if item ~= nil and item.used and item.item_id == ITEM_ARROW and item.count > 0 then
            return slot, item
        end
    end
    return nil, nil
end

local function consume_arrow(player)
    local slot, item = find_arrow(player)
    if slot == nil then
        return false
    end
    local remaining = item.count - 1
    if remaining == 0 then
        return mcs_player_set_inventory_item(player.username, slot, ITEM_AIR, 0, nil)
    end
    return mcs_player_set_inventory_item(player.username, slot, ITEM_ARROW, remaining, nil)
end

local function consume_selected_item(player, expected_item_id)
    local slot = player.selected_inventory_id
    local item = mcs_player_get_inventory_info(player.username, slot)
    if item == nil or not item.used or item.item_id ~= expected_item_id or item.count <= 0 then
        return false
    end
    local remaining = item.count - 1
    return mcs_player_set_inventory_item(
        player.username,
        slot,
        remaining > 0 and expected_item_id or ITEM_AIR,
        remaining,
        remaining > 0 and item.nbt_data or nil
    )
end

local function segment_aabb_t(x0, y0, z0, x1, y1, z1, min_x, min_y, min_z, max_x, max_y, max_z)
    local t_min = 0.0
    local t_max = 1.0
    local starts = { x0, y0, z0 }
    local deltas = { x1 - x0, y1 - y0, z1 - z0 }
    local minimums = { min_x, min_y, min_z }
    local maximums = { max_x, max_y, max_z }

    for axis = 1, 3 do
        local start = starts[axis]
        local delta = deltas[axis]
        if math.abs(delta) < 0.0000001 then
            if start < minimums[axis] or start > maximums[axis] then
                return nil
            end
        else
            local inverse = 1.0 / delta
            local near_t = (minimums[axis] - start) * inverse
            local far_t = (maximums[axis] - start) * inverse
            if near_t > far_t then
                near_t, far_t = far_t, near_t
            end
            t_min = math.max(t_min, near_t)
            t_max = math.min(t_max, far_t)
            if t_min > t_max then
                return nil
            end
        end
    end
    return t_min
end

local function solid_block_hit_t(x0, y0, z0, x1, y1, z1)
    local dx = x1 - x0
    local dy = y1 - y0
    local dz = z1 - z0
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local steps = math.max(1, math.ceil(distance / PROJECTILE_COLLISION_STEP))

    for step = 1, steps do
        local t = step / steps
        if mcs_block_is_solid(
                math.floor(x0 + dx * t),
                math.floor(y0 + dy * t),
                math.floor(z0 + dz * t)
            ) then
            return t
        end
    end
    return nil
end

local function set_observer(name)
    observer_names[name] = true
    mcs_player_set_armor_value(name, 0)
    mcs_player_set_gamemode(name, "adventure")
    mcs_player_set_allow_flying(name, true)
    mcs_player_hide(name)
end

local function send_to_lobby(playername)
    if returned_to_lobby[playername] then
        return true
    end
    if proxy_transfer.connect(
            playername,
            LOBBY_SERVER_NAME,
            LOBBY_HOST,
            LOBBY_PORT
        ) then
        returned_to_lobby[playername] = true
        return true
    end
    tell(playername, "暂时无法连接大厅，请右键床或使用 /hub 重试。", "red", true)
    return false
end

local function alive_entries()
    local alive = {}
    for _, entry in ipairs(participants) do
        if entry.alive and entry.connected then
            alive[#alive + 1] = entry
        end
    end
    return alive
end

local function refresh_waiting_status()
    local text = string.format("等待玩家：%d/%d", #participants, MAX_PLAYERS)
    local remaining_ticks = waiting_countdown and waiting_countdown.remaining_ticks() or 0
    if #participants >= MIN_PLAYERS and remaining_ticks > 0 then
        local seconds = math.ceil(remaining_ticks / TICKS_PER_SECOND)
        text = string.format("%s · %d 秒后开始", text, seconds)
    end
    for _, entry in ipairs(participants) do
        mcs_title_set_action_bar_text(entry.name, component(text, "yellow", true))
    end
end

local function refresh_alive_status()
    local alive = alive_entries()
    local text = string.format("剩余玩家：%d", #alive)
    for _, entry in ipairs(participants) do
        if entry.connected then
            mcs_title_set_action_bar_text(entry.name, component(text, "aqua", true))
        end
    end
end

local function award_winner(entry)
    local economy_transaction = rawget(_G, "oakmc_economy_transaction")
    local rewarded = false
    local balance

    if type(economy_transaction) == "function" then
        local called, success, value = pcall(
            economy_transaction,
            entry.name,
            WINNER_REWARD_COINS,
            0
        )
        rewarded = called and success == true
        balance = value
    end

    mcs_player_set_inventory_item(
        entry.name,
        WINNER_TROPHY_SLOT,
        ITEM_NETHER_STAR,
        1,
        component("PVP 胜利之星", "gold", true)
    )

    if rewarded then
        tell(
            entry.name,
            string.format("胜利奖励：+%d 金币，当前余额 %s", WINNER_REWARD_COINS, tostring(balance)),
            "gold",
            true
        )
    else
        tell(entry.name, "已获得 PVP 胜利之星；金币服务暂时不可用。", "gold", true)
        mcs_server_send_message(
            "[pvp] Failed to grant persistent reward to " .. entry.name,
            MCS_LOG_WARN
        )
    end
end

local function finish_match(winner)
    if state ~= STATE_FIGHTING then
        return
    end

    state = STATE_FINISHED
    finish_ticks = RETURN_DELAY_TICKS
    stop_all_bow_charges()

    if winner ~= nil then
        award_winner(winner)
        broadcast("本局获胜者：" .. winner.name .. "！", "gold", true)
    else
        broadcast("本局无人获胜。", "yellow", true)
    end

    for _, entry in ipairs(participants) do
        if entry.connected then
            mcs_title_set_time(entry.name, 5, 70, 15)
            if winner ~= nil and entry.name == winner.name then
                mcs_title_set_subtitle_text(entry.name, component("奖励已发放，5 秒后返回大厅", "yellow", false))
                mcs_title_set_text(entry.name, component("胜利！", "gold", true))
                mcs_player_play_sound_name(
                    entry.name,
                    "minecraft:ui.toast.challenge_complete",
                    0,
                    1.0,
                    1.0,
                    0
                )
            else
                mcs_title_set_subtitle_text(entry.name, component("5 秒后返回大厅", "gray", false))
                mcs_title_set_text(entry.name, component("游戏结束", "red", true))
            end
        end
    end
end

local function check_for_winner()
    if state ~= STATE_FIGHTING then
        return
    end

    local alive = alive_entries()
    refresh_alive_status()
    if #alive == 1 then
        finish_match(alive[1])
    elseif #alive == 0 then
        finish_match(nil)
    end
end

local function eliminate(entry, killer_name, reason, defer_winner_check)
    if state ~= STATE_FIGHTING or entry == nil or not entry.alive then
        return
    end

    entry.alive = false
    stop_bow_charge(entry.name)
    mcs_player_update_health(entry.name, 20, 20, DEFAULT_FOOD_SATURATION)
    set_observer(entry.name)
    clear_inventory(entry.name)
    sync_held_item(entry.name)
    return_bed.add(entry.name)

    if killer_name ~= nil then
        broadcast(entry.name .. " 被 " .. killer_name .. " 淘汰", "red", false)
    else
        broadcast(entry.name .. " " .. (reason or "被淘汰"), "red", false)
    end
    tell(entry.name, "你已被淘汰。右键物品栏中的床可以返回大厅。", "gray", false)
    mcs_player_play_sound_name(entry.name, "minecraft:entity.wither.death", 0, 0.7, 1.2, 0)
    if not defer_winner_check then
        check_for_winner()
    end
end

local function start_match(force)
    if state ~= STATE_WAITING or #participants == 0 then
        return
    end
    if force and #participants < MIN_PLAYERS then
        return
    end
    if not force and #participants < MAX_PLAYERS then
        return
    end

    state = STATE_FIGHTING
    waiting_countdown.reset()
    for _, entry in ipairs(participants) do
        entry.alive = true
        entry.connected = true
        entry.last_damage_tick = tick_count
        observer_names[entry.name] = nil
        returned_to_lobby[entry.name] = nil
        stop_bow_charge(entry.name)
        return_bed.remove(entry.name)
        mcs_player_show(entry.name)
        mcs_player_set_allow_flying(entry.name, false)
        clear_inventory(entry.name)
        mcs_player_set_gamemode(entry.name, "survival")
        mcs_player_update_health(entry.name, 20, 20, DEFAULT_FOOD_SATURATION)
        give_combat_loadout(entry.name)
        equip_diamond_armor(entry.name)
        sync_held_item(entry.name)
        teleport_to_pad(entry)
        initialize_combat_state(entry, mcs_player_get_info_by_name(entry.name))
        mcs_title_set_time(entry.name, 5, 30, 10)
        mcs_title_set_subtitle_text(entry.name, component("最后存活的玩家获胜", "yellow", false))
        mcs_title_set_text(entry.name, component("战斗开始！", "red", true))
        mcs_player_play_sound_name(
            entry.name,
            "minecraft:entity.ender_dragon.growl",
            0,
            0.6,
            1.35,
            0
        )
    end
    broadcast(string.format("%d 名玩家进入对局，PVP 战斗开始！", #participants), "red", true)
    refresh_alive_status()
end

local function add_waiting_player(name)
    if participant_by_name[name] ~= nil then
        return participant_by_name[name]
    end
    if #participants >= MAX_PLAYERS then
        return nil
    end

    local entry = {
        name = name,
        slot = #participants + 1,
        alive = false,
        connected = true,
        last_damage_tick = 0,
        last_attack_tick = 0,
        last_hurt_tick = 0,
        regen_tick = 0,
        food_exhaustion = 0.0,
        sprint_attack_consumed = false,
        motion = nil,
    }
    participants[#participants + 1] = entry
    participant_by_name[name] = entry
    returned_to_lobby[name] = nil
    clear_inventory(name)
    return_bed.add(name)
    mcs_player_set_gamemode(name, "survival")
    mcs_player_set_armor_value(name, 0)
    mcs_player_update_health(name, 20, 20, DEFAULT_FOOD_SATURATION)
    teleport_to_pad(entry)
    tell(
        name,
        string.format(
            "你已加入 PVP，正在等待其他玩家（%d/%d）。右键床可返回大厅。",
            #participants,
            MAX_PLAYERS
        ),
        "aqua",
        false
    )
    waiting_countdown.changed()
    return entry
end

local function make_observer(name)
    clear_inventory(name)
    sync_held_item(name)
    set_observer(name)
    mcs_player_update_health(name, 20, 20, DEFAULT_FOOD_SATURATION)
    return_bed.add(name)
    tell(name, "对局已经开始，你将以旁观者身份观看。右键床可返回大厅。", "gray", false)
end

local function on_player_initialized(event)
    local name = player_name(event)
    if name == nil then
        return
    end

    local existing = participant_by_name[name]
    if state == STATE_WAITING then
        add_waiting_player(name)
    elseif existing ~= nil and existing.alive and existing.connected then
        -- A plugin reload during a live match should preserve an already
        -- initialized participant as closely as possible.
        mcs_player_set_gamemode(name, "survival")
    else
        if existing ~= nil then
            existing.connected = true
            existing.alive = false
        end
        make_observer(name)
    end
end

local function remove_waiting_player(entry)
    participant_by_name[entry.name] = nil
    for index, candidate in ipairs(participants) do
        if candidate == entry then
            table.remove(participants, index)
            break
        end
    end
    for index, candidate in ipairs(participants) do
        candidate.slot = index
        teleport_to_pad(candidate)
    end
    waiting_countdown.changed()
end

local function on_player_quit(event)
    local name = player_name(event)
    if name == nil then
        return
    end
    local entry = participant_by_name[name]
    stop_bow_charge(name)
    returned_to_lobby[name] = nil
    observer_names[name] = nil
    return_bed.remove(name)
    if entry == nil then
        return
    end

    entry.connected = false
    if state == STATE_WAITING then
        remove_waiting_player(entry)
    elseif state == STATE_FIGHTING and entry.alive then
        entry.alive = false
        broadcast(entry.name .. " 离开服务器并被淘汰", "red", false)
        check_for_winner()
    end
end

local function apply_directional_knockback(
    target_entry,
    nx,
    nz,
    horizontal_knockback,
    vertical_knockback
)
    local target = mcs_player_get_info_by_name(target_entry.name)
    if target == nil then
        return
    end

    local motion = target_entry.motion or {}
    local velocity_x = (motion.vx or 0.0) * KNOCKBACK_MOTION_DAMPING +
        nx * horizontal_knockback
    local velocity_z = (motion.vz or 0.0) * KNOCKBACK_MOTION_DAMPING +
        nz * horizontal_knockback
    local velocity_y = motion.vy or 0.0
    if target.on_ground then
        velocity_y = math.min(
            KNOCKBACK_VERTICAL,
            velocity_y * KNOCKBACK_MOTION_DAMPING + vertical_knockback
        )
    end

    mcs_player_sync_position_with_velocity(
        target_entry.name,
        target.x,
        target.y,
        target.z,
        velocity_x,
        velocity_y,
        velocity_z,
        target.yaw,
        target.pitch
    )
end

local function is_within_melee_reach(attacker, target)
    local eye_x = attacker.x
    local eye_y = attacker.y + PLAYER_EYE_HEIGHT
    local eye_z = attacker.z
    local function distance_to_axis(value, minimum, maximum)
        if value < minimum then
            return minimum - value
        end
        if value > maximum then
            return value - maximum
        end
        return 0.0
    end
    local dx = distance_to_axis(
        eye_x,
        target.x - PLAYER_HITBOX_RADIUS,
        target.x + PLAYER_HITBOX_RADIUS
    )
    local dy = distance_to_axis(eye_y, target.y, target.y + PLAYER_HITBOX_HEIGHT)
    local dz = distance_to_axis(
        eye_z,
        target.z - PLAYER_HITBOX_RADIUS,
        target.z + PLAYER_HITBOX_RADIUS
    )
    return dx * dx + dy * dy + dz * dz <= MELEE_REACH * MELEE_REACH
end

local function is_critical_attack(attacker_entry, attacker_info, strength)
    local motion = attacker_entry.motion
    return strength > FULL_ATTACK_THRESHOLD and
        not attacker_info.on_ground and
        not attacker_info.is_flying and
        motion ~= nil and not motion.sprinting and
        motion.vy < -MOTION_EPSILON
end

local function apply_melee_knockback(target_entry, attacker_entry, attacker_info, strength)
    local yaw_radians = math.rad(attacker_info.yaw)
    local nx = -math.sin(yaw_radians)
    local nz = math.cos(yaw_radians)
    local sprint_attack = strength > FULL_ATTACK_THRESHOLD and
        attacker_entry.motion ~= nil and attacker_entry.motion.sprinting and
        not attacker_entry.sprint_attack_consumed
    local strength_scale = 0.2 + strength * 0.8
    local horizontal = KNOCKBACK_HORIZONTAL * strength_scale
    if sprint_attack then
        horizontal = horizontal + KNOCKBACK_SPRINT_BONUS
        attacker_entry.sprint_attack_consumed = true
    end
    apply_directional_knockback(
        target_entry,
        nx,
        nz,
        horizontal,
        KNOCKBACK_VERTICAL * strength_scale
    )
    return sprint_attack
end

local function on_attack(event)
    if state ~= STATE_FIGHTING or event.target_playername == nil then
        return
    end

    local attacker_name = event.attacker_playername or event.attacker_username
    if attacker_name == nil and event.attacker_entity_id ~= nil then
        local attacker_info = mcs_entity_get_info_by_id(event.attacker_entity_id)
        attacker_name = attacker_info and attacker_info.username or nil
    end

    local attacker = attacker_name and participant_by_name[attacker_name] or nil
    local target = participant_by_name[event.target_playername]
    if attacker == nil or target == nil or not attacker.alive or not target.alive or
        not attacker.connected or not target.connected or attacker == target then
        return
    end

    local target_info = mcs_player_get_info_by_name(target.name)
    if target_info == nil then
        return
    end

    local attacker_info = mcs_player_get_info_by_name(attacker.name)
    if attacker_info == nil or not is_within_melee_reach(attacker_info, target_info) then
        return
    end
    local held = mcs_player_get_inventory_info(
        attacker.name,
        attacker_info.selected_inventory_id or 0
    )
    local strength = attack_strength(attacker, held)
    attacker.last_attack_tick = tick_count
    attacker.food_exhaustion = (attacker.food_exhaustion or 0.0) + ATTACK_EXHAUSTION

    if tick_count - (target.last_hurt_tick or 0) < HURT_RESISTANCE_TICKS then
        return
    end

    local raw_damage = held ~= nil and held.used and held.item_id == ITEM_DIAMOND_SWORD
        and SWORD_ATTACK_DAMAGE or ATTACK_DAMAGE
    raw_damage = raw_damage * (0.2 + strength * strength * 0.8)
    if is_critical_attack(attacker, attacker_info, strength) then
        raw_damage = raw_damage * CRITICAL_DAMAGE_MULTIPLIER
    end
    local damage = damage_after_diamond_armor(raw_damage)
    if target_info.health <= damage then
        eliminate(target, attacker.name)
        return
    end

    if mcs_player_apply_damage(target.name, event.attacker_entity_id, damage, 0) then
        target.last_hurt_tick = tick_count
        target.last_damage_tick = tick_count
        target.regen_tick = 0
        apply_melee_knockback(target, attacker, attacker_info, strength)
    end
end

local function projectile_player_hit(projectile, x0, y0, z0, x1, y1, z1, players, block_t)
    local best_player = nil
    local best_t = block_t or math.huge

    for _, player in ipairs(players) do
        local entry = player.username and participant_by_name[player.username] or nil
        local can_hit = state == STATE_FIGHTING and entry ~= nil and entry.alive and
            entry.connected and player.play_initialized and player.health > 0 and
            player.dimension_id == projectile.dimension_id
        if can_hit and
            (player.entity_id ~= projectile.shooter_entity_id or
                projectile.age >= SHOOTER_GRACE_TICKS) then
            local hit_t = segment_aabb_t(
                x0,
                y0,
                z0,
                x1,
                y1,
                z1,
                player.x - PLAYER_HITBOX_RADIUS,
                player.y,
                player.z - PLAYER_HITBOX_RADIUS,
                player.x + PLAYER_HITBOX_RADIUS,
                player.y + PLAYER_HITBOX_HEIGHT,
                player.z + PLAYER_HITBOX_RADIUS
            )
            if hit_t ~= nil and hit_t < best_t then
                best_t = hit_t
                best_player = player
            end
        end
    end
    return best_player
end

local function remove_projectile(index)
    local projectile = projectiles[index]
    if projectile ~= nil then
        mcs_entity_remove(projectile.entity_id)
        table.remove(projectiles, index)
    end
end

local function clear_projectiles()
    for index = #projectiles, 1, -1 do
        remove_projectile(index)
    end
end

local function fire_arrow(player, power)
    if #projectiles >= MAX_ACTIVE_PROJECTILES then
        tell(player.username, "场上的投掷物太多了，请稍后再射。", "red", false)
        return false
    end

    local dir_x, dir_y, dir_z = direction_from_rotation(player.yaw, player.pitch)
    local speed = 3.0 * power
    local spawn_x = player.x + dir_x * 0.16
    local spawn_y = player.y + PLAYER_EYE_HEIGHT + dir_y * 0.16
    local spawn_z = player.z + dir_z * 0.16
    local vx = dir_x * speed
    local vy = dir_y * speed
    local vz = dir_z * speed
    local yaw, pitch = projectile_rotation(vx, vy, vz)
    local entity_id = mcs_entity_spawn_with_velocity(
        ARROW_ENTITY_TYPE,
        spawn_x,
        spawn_y,
        spawn_z,
        vx,
        vy,
        vz,
        yaw,
        pitch,
        yaw,
        player.entity_id
    )
    if entity_id == nil or entity_id == false then
        mcs_server_send_message("[pvp] Failed to spawn arrow for " .. player.username, MCS_LOG_WARN)
        return false
    end

    projectiles[#projectiles + 1] = {
        entity_id = entity_id,
        shooter_entity_id = player.entity_id,
        shooter_name = player.username,
        dimension_id = player.dimension_id,
        x = spawn_x,
        y = spawn_y,
        z = spawn_z,
        vx = vx,
        vy = vy,
        vz = vz,
        age = 0,
        kind = "arrow",
        gravity = PROJECTILE_GRAVITY,
        embedded = false,
        embedded_age = 0,
        critical = power >= 1.0,
    }
    mcs_player_play_sound_name(
        player.username,
        "minecraft:entity.arrow.shoot",
        0,
        1.0,
        1.0 + power * 0.2,
        tick_count
    )
    return true
end

local function throw_snowball(player)
    if #projectiles >= MAX_ACTIVE_PROJECTILES then
        tell(player.username, "场上的投掷物太多了，请稍后再投。", "red", false)
        return false
    end

    local dir_x, dir_y, dir_z = direction_from_rotation(player.yaw, player.pitch)
    local spawn_x = player.x + dir_x * 0.16
    local spawn_y = player.y + PLAYER_EYE_HEIGHT + dir_y * 0.16
    local spawn_z = player.z + dir_z * 0.16
    local vx = dir_x * SNOWBALL_SPEED
    local vy = dir_y * SNOWBALL_SPEED
    local vz = dir_z * SNOWBALL_SPEED
    local yaw, pitch = projectile_rotation(vx, vy, vz)
    local entity_id = mcs_entity_spawn_with_velocity(
        SNOWBALL_ENTITY_TYPE,
        spawn_x,
        spawn_y,
        spawn_z,
        vx,
        vy,
        vz,
        yaw,
        pitch,
        yaw,
        player.entity_id
    )
    if entity_id == nil or entity_id == false then
        mcs_server_send_message(
            "[pvp] Failed to spawn snowball for " .. player.username,
            MCS_LOG_WARN
        )
        return false
    end

    projectiles[#projectiles + 1] = {
        entity_id = entity_id,
        shooter_entity_id = player.entity_id,
        shooter_name = player.username,
        dimension_id = player.dimension_id,
        x = spawn_x,
        y = spawn_y,
        z = spawn_z,
        vx = vx,
        vy = vy,
        vz = vz,
        age = 0,
        kind = "snowball",
        gravity = SNOWBALL_GRAVITY,
        embedded = false,
        embedded_age = 0,
        critical = false,
    }
    mcs_player_play_sound_name(
        player.username,
        "minecraft:entity.snowball.throw",
        0,
        0.8,
        1.0,
        tick_count
    )
    return true
end

local function update_flying_projectile(index, projectile, players)
    local old_x = projectile.x
    local old_y = projectile.y
    local old_z = projectile.z
    local new_x = old_x + projectile.vx
    local new_y = old_y + projectile.vy
    local new_z = old_z + projectile.vz
    local block_t = solid_block_hit_t(old_x, old_y, old_z, new_x, new_y, new_z)
    local target = projectile_player_hit(
        projectile,
        old_x,
        old_y,
        old_z,
        new_x,
        new_y,
        new_z,
        players,
        block_t
    )

    projectile.age = projectile.age + 1
    if target ~= nil then
        local target_entry = participant_by_name[target.username]
        if projectile.kind == "snowball" then
            mcs_player_hurt_animation_for_all(
                target.entity_id,
                projectile_hurt_yaw(target, projectile)
            )
            local horizontal_speed = math.sqrt(
                projectile.vx * projectile.vx + projectile.vz * projectile.vz
            )
            if target_entry ~= nil and horizontal_speed > KNOCKBACK_MIN_DISTANCE then
                apply_directional_knockback(
                    target_entry,
                    projectile.vx / horizontal_speed,
                    projectile.vz / horizontal_speed,
                    SNOWBALL_KNOCKBACK_HORIZONTAL,
                    KNOCKBACK_VERTICAL
                )
            end
            remove_projectile(index)
            return
        end

        local speed = math.sqrt(
            projectile.vx * projectile.vx +
            projectile.vy * projectile.vy +
            projectile.vz * projectile.vz
        )
        local damage = math.max(1, math.ceil(speed * 2.0))
        if projectile.critical then
            damage = damage + math.random(0, math.floor(damage / 2) + 1)
        end
        damage = damage_after_diamond_armor(damage)

        local hurt_resistant = target_entry ~= nil and
            tick_count - (target_entry.last_hurt_tick or 0) < HURT_RESISTANCE_TICKS
        if target_entry ~= nil and not hurt_resistant and target.health <= damage then
            eliminate(target_entry, projectile.shooter_name)
        elseif target_entry ~= nil and not hurt_resistant then
            local damaged = mcs_player_apply_damage(
                target.username,
                projectile.shooter_entity_id,
                damage,
                0
            )
            if damaged then
                target_entry.last_hurt_tick = tick_count
                target_entry.last_damage_tick = tick_count
                target_entry.regen_tick = 0
            end
            local horizontal_speed = math.sqrt(
                projectile.vx * projectile.vx + projectile.vz * projectile.vz
            )
            if damaged and horizontal_speed > KNOCKBACK_MIN_DISTANCE then
                apply_directional_knockback(
                    target_entry,
                    projectile.vx / horizontal_speed,
                    projectile.vz / horizontal_speed,
                    KNOCKBACK_HORIZONTAL,
                    KNOCKBACK_VERTICAL
                )
            end
        end
        remove_projectile(index)
        return
    end

    if block_t ~= nil then
        if projectile.kind == "snowball" then
            remove_projectile(index)
            return
        end
        local hit_x = old_x + (new_x - old_x) * block_t
        local hit_y = old_y + (new_y - old_y) * block_t
        local hit_z = old_z + (new_z - old_z) * block_t
        local yaw, pitch = projectile_rotation(projectile.vx, projectile.vy, projectile.vz)
        projectile.x = hit_x
        projectile.y = hit_y
        projectile.z = hit_z
        projectile.vx = 0.0
        projectile.vy = 0.0
        projectile.vz = 0.0
        projectile.embedded = true
        projectile.embedded_age = 0
        if not mcs_entity_move(
                projectile.entity_id,
                hit_x,
                hit_y,
                hit_z,
                0.0,
                0.0,
                0.0,
                yaw,
                pitch,
                yaw,
                true
            ) then
            table.remove(projectiles, index)
        end
        return
    end

    if projectile.age >= MAX_PROJECTILE_TICKS or new_y < -80.0 or new_y > 400.0 then
        remove_projectile(index)
        return
    end

    projectile.x = new_x
    projectile.y = new_y
    projectile.z = new_z
    projectile.vx = projectile.vx * PROJECTILE_AIR_DRAG
    projectile.vy = projectile.vy * PROJECTILE_AIR_DRAG -
        (projectile.gravity or PROJECTILE_GRAVITY)
    projectile.vz = projectile.vz * PROJECTILE_AIR_DRAG
end

local function update_projectiles()
    local players = mcs_player_list_info() or {}
    for index = #projectiles, 1, -1 do
        if state ~= STATE_FIGHTING then
            break
        end
        local projectile = projectiles[index]
        if projectile.embedded then
            projectile.embedded_age = projectile.embedded_age + 1
            if projectile.embedded_age >= MAX_EMBEDDED_TICKS then
                remove_projectile(index)
            end
        else
            update_flying_projectile(index, projectile, players)
        end
    end
    if state ~= STATE_FIGHTING and #projectiles > 0 then
        clear_projectiles()
    end
end

local function update_bow_charges()
    local interrupted = {}
    for name in pairs(bow_charging) do
        local entry = participant_by_name[name]
        local player = mcs_player_get_info_by_name(name)
        local held = player ~= nil and
            mcs_player_get_inventory_info(name, player.selected_inventory_id) or nil
        if state ~= STATE_FIGHTING or entry == nil or not entry.alive or
            not entry.connected or player == nil or not player.play_initialized or
            held == nil or not held.used or held.item_id ~= ITEM_BOW then
            interrupted[#interrupted + 1] = name
        end
    end
    for _, name in ipairs(interrupted) do
        stop_bow_charge(name)
    end
end

local function start_bow_charge(event, entry, player)
    if event.hand ~= nil and event.hand ~= MAIN_HAND then
        return false
    end
    local held = mcs_player_get_inventory_info(player.username, player.selected_inventory_id)
    if held == nil or not held.used or held.item_id ~= ITEM_BOW then
        return false
    end
    if state ~= STATE_FIGHTING or entry == nil or not entry.alive or not entry.connected then
        return false
    end
    if find_arrow(player) == nil then
        return false
    end
    if bow_charging[player.username] == nil then
        local hand = event.hand or MAIN_HAND
        bow_charging[player.username] = {
            start_tick = tick_count,
            entity_id = player.entity_id,
            hand = hand,
        }
        broadcast_bow_animation(player.entity_id, true, hand)
    end
    event.cancelled = true
    return true
end

local function on_release_use_item(event)
    local name = player_name(event)
    local charge = name ~= nil and stop_bow_charge(name) or nil
    if charge == nil then
        return
    end
    event.cancelled = true
    if event.item_id ~= ITEM_BOW then
        return
    end

    local entry = participant_by_name[name]
    local player = mcs_player_get_info_by_name(name)
    if state ~= STATE_FIGHTING or entry == nil or not entry.alive or
        not entry.connected or player == nil or not player.play_initialized then
        return
    end
    local held = mcs_player_get_inventory_info(name, player.selected_inventory_id)
    if held == nil or not held.used or held.item_id ~= ITEM_BOW then
        return
    end

    local charged_ticks = tick_count - charge.start_tick
    if charged_ticks < MIN_BOW_CHARGE_TICKS then
        return
    end
    local power = bow_charge_power(charged_ticks)
    if power < 0.1 then
        return
    end
    if not consume_arrow(player) then
        tell(name, "没有箭，无法射击。", "red", false)
        return
    end
    fire_arrow(player, power)
end

local function is_wool_block_state(block_state_id)
    return block_state_id ~= nil and
        block_state_id >= WHITE_WOOL_BLOCK_STATE and
        block_state_id <= BLACK_WOOL_BLOCK_STATE
end

local function on_block_break(event)
    local name = player_name(event)
    local entry = name and participant_by_name[name] or nil
    if state ~= STATE_FIGHTING or entry == nil or not entry.alive or
        not entry.connected or not is_wool_block_state(event.block_state_id) then
        event.cancelled = true
    end
end

local function on_held_item_change(event)
    local name = player_name(event)
    local entry = name and participant_by_name[name] or nil
    if state == STATE_FIGHTING and entry ~= nil and entry.alive and entry.connected then
        sync_held_item(name)
    end
end

local function on_use_item(event)
    local name = player_name(event)
    local entry = name and participant_by_name[name] or nil
    if name == nil then
        return
    end
    if event.item_id == ITEM_BOW then
        local player = mcs_player_get_info_by_name(name)
        event.cancelled = true
        if player ~= nil and not start_bow_charge(event, entry, player) and
            find_arrow(player) == nil then
            tell(name, "没有箭，无法拉弓。", "red", false)
        end
        return
    end
    if event.item_id == ITEM_SNOWBALL and state == STATE_FIGHTING and
        entry ~= nil and entry.alive and entry.connected then
        local player = mcs_player_get_info_by_name(name)
        event.cancelled = true
        if player ~= nil and consume_selected_item(player, ITEM_SNOWBALL) then
            throw_snowball(player)
        end
        return
    end
    if event.item_id == ITEM_POTION and state == STATE_FIGHTING and
        entry ~= nil and entry.alive and entry.connected then
        local player = mcs_player_get_info_by_name(name)
        event.cancelled = true
        if player ~= nil and consume_selected_item(player, ITEM_POTION) then
            mcs_player_set_effect(
                name,
                "speed",
                SPEED_EFFECT_AMPLIFIER,
                SPEED_EFFECT_SECONDS,
                "particles,icon"
            )
            mcs_player_play_sound_name(
                name,
                "minecraft:entity.generic.drink",
                0,
                0.8,
                1.1,
                tick_count
            )
        end
        return
    end
    if event.item_id == ITEM_SPLASH_POTION and state == STATE_FIGHTING and
        entry ~= nil and entry.alive and entry.connected then
        local info = mcs_player_get_info_by_name(name)
        if info == nil then
            return
        end
        event.cancelled = true
        mcs_player_set_inventory_item(name, info.selected_inventory_id, ITEM_AIR, 0, nil)
        mcs_player_set_effect(name, "instant_health", 0, 1, "particles,icon")
        mcs_player_update_health(
            name,
            math.min(20, info.health + HEAL_AMOUNT),
            info.food,
            info.food_saturation
        )
        mcs_player_play_sound_name(name, "minecraft:entity.generic.splash", 0, 0.8, 1.2, 0)
        return
    end
    if event.item_id ~= ITEM_RED_BED then
        return
    end
    return_bed.use(event, function(playername)
        local player_entry = participant_by_name[playername]
        return not (player_entry ~= nil and player_entry.alive and state == STATE_FIGHTING)
    end)
end

local function return_all_players()
    for _, info in ipairs(mcs_player_list_info() or {}) do
        if info.username ~= nil then
            send_to_lobby(info.username)
        end
    end
end

local function update_natural_regeneration(entry, info)
    local health = info.health
    local food = info.food
    local saturation = info.food_saturation
    local exhaustion = entry.food_exhaustion or 0.0
    local motion = entry.motion

    if motion ~= nil and motion.sprinting then
        exhaustion = exhaustion + motion.horizontal_speed * SPRINT_EXHAUSTION_PER_BLOCK
    end
    if info.is_jump then
        exhaustion = exhaustion +
            (motion ~= nil and motion.sprinting and SPRINT_JUMP_EXHAUSTION or WALK_JUMP_EXHAUSTION)
    end

    while exhaustion > FOOD_EXHAUSTION_THRESHOLD do
        exhaustion = exhaustion - FOOD_EXHAUSTION_THRESHOLD
        if saturation > 0.0 then
            saturation = math.max(0.0, saturation - 1.0)
        elseif food > 0 then
            food = food - 1
        end
    end

    if health >= 20.0 or food < NATURAL_REGEN_MIN_FOOD then
        entry.regen_tick = 0
    elseif food >= 20 and saturation > 0.0 then
        entry.regen_tick = (entry.regen_tick or 0) + 1
        if entry.regen_tick >= SATURATED_REGEN_INTERVAL_TICKS then
            local consumed = math.min(saturation, SATURATED_REGEN_MAX_EXHAUSTION)
            health = math.min(20.0, health + consumed / 6.0)
            exhaustion = exhaustion + consumed
            entry.regen_tick = 0
        end
    else
        entry.regen_tick = (entry.regen_tick or 0) + 1
        if entry.regen_tick >= HUNGRY_REGEN_INTERVAL_TICKS then
            health = math.min(20.0, health + HUNGRY_REGEN_AMOUNT)
            exhaustion = exhaustion + HUNGRY_REGEN_EXHAUSTION
            entry.regen_tick = 0
        end
    end

    entry.food_exhaustion = exhaustion
    if health ~= info.health or food ~= info.food or saturation ~= info.food_saturation then
        mcs_player_update_health(entry.name, health, food, saturation)
    end
end

local function on_server_tick()
    tick_count = tick_count + 1
    for _, entry in ipairs(participants) do
        if entry.connected then
            update_player_motion(entry)
        end
    end
    update_bow_charges()
    if state == STATE_FIGHTING then
        update_projectiles()
    elseif #projectiles > 0 then
        clear_projectiles()
    end

    -- Drop-item packets are client-predicted while OakMC keeps the
    -- authoritative slot unchanged. The reusable bed helper force-syncs
    -- tracked waiting players and observers every tick.
    return_bed.sync()

    if state == STATE_WAITING then
        waiting_countdown.tick()
        return
    end

    if state == STATE_FIGHTING then
        for _, entry in ipairs(participants) do
            if entry.alive and entry.connected then
                sync_held_item(entry.name)
            end
        end
        if tick_count % ARMOR_SYNC_TICKS == 0 then
            for _, entry in ipairs(participants) do
                if entry.alive and entry.connected then
                    -- Armor is visual server-owned equipment, not an
                    -- inventory stack the client can remove. Re-broadcast it
                    -- periodically to repair any client-side prediction.
                    equip_diamond_armor(entry.name)
                end
            end
        end
        local eliminated = {}
        for _, entry in ipairs(participants) do
            if entry.alive and entry.connected then
                local info = mcs_player_get_info_by_name(entry.name)
                if info == nil or info.health <= 0 or info.y < ELIMINATION_Y then
                    eliminated[#eliminated + 1] = entry
                else
                    update_natural_regeneration(entry, info)
                end
            end
        end
        for _, entry in ipairs(eliminated) do
            eliminate(entry, nil, "跌出竞技场并被淘汰", true)
        end
        if #eliminated > 0 then
            check_for_winner()
        end
        return
    end

    if state ~= STATE_FINISHED or finish_ticks <= 0 then
        return
    end

    finish_ticks = finish_ticks - 1
    if finish_ticks == 0 then
        return_all_players()
        return
    end

    if finish_ticks % TICKS_PER_SECOND == 0 then
        local seconds = math.ceil(finish_ticks / TICKS_PER_SECOND)
        for _, entry in ipairs(participants) do
            if entry.connected and not returned_to_lobby[entry.name] then
                mcs_title_set_action_bar_text(
                    entry.name,
                    component(string.format("%d 秒后返回大厅", seconds), "yellow", true)
                )
            end
        end
    end
end

local function configure_world()
    mcs_world_set_default_spawn_position(
        "minecraft:overworld",
        ARENA_CENTER.x,
        ARENA_CENTER.y,
        ARENA_CENTER.z,
        ARENA_CENTER.yaw,
        ARENA_CENTER.pitch
    )
end

local function initialize_loaded_players()
    for _, info in ipairs(mcs_player_list_info() or {}) do
        if info.username ~= nil and info.play_initialized then
            on_player_initialized({ username = info.username })
        end
    end
end

local function init()
    state = STATE_WAITING
    participants = {}
    participant_by_name = {}
    finish_ticks = 0
    returned_to_lobby = {}
    observer_names = {}
    tick_count = 0
    bow_charging = {}
    projectiles = {}
    held_item_display = {}

    return_bed = waiting_room.return_bed({
        item_id = ITEM_RED_BED,
        slot = RETURN_BED_SLOT,
        give = function(name)
            give_return_bed(name)
        end,
        return_player = send_to_lobby,
        can_sync = function(name)
            local info = mcs_player_get_info_by_name(name)
            return info ~= nil and info.play_initialized
        end,
    })
    waiting_countdown = waiting_room.countdown({
        min_players = MIN_PLAYERS,
        max_players = MAX_PLAYERS,
        timeout_ticks = WAIT_TIMEOUT_TICKS,
        ticks_per_second = TICKS_PER_SECOND,
        count = function()
            return #participants
        end,
        on_status = refresh_waiting_status,
        on_start = start_match,
    })

    mcs_event_register(MCS_EVENT_PLAYER_INITIALIZED, 100, on_player_initialized)
    mcs_event_register(MCS_EVENT_PLAYER_QUIT, 100, on_player_quit)
    mcs_event_register(MCS_EVENT_ENTITY_ATTACK, 100, on_attack)
    mcs_event_register(MCS_EVENT_BLOCK_BREAK, 100, on_block_break)
    mcs_event_register(MCS_EVENT_USE_ITEM, 100, on_use_item)
    mcs_event_register(MCS_EVENT_RELEASE_USE_ITEM, 100, on_release_use_item)
    mcs_event_register(MCS_EVENT_HELD_ITEM_CHANGE, 100, on_held_item_change, { cancellable = false })
    mcs_event_register(MCS_EVENT_SERVER_TICK, 100, on_server_tick, { cancellable = false })
    mcs_event_register(MCS_EVENT_SERVER_START, 100, configure_world, { cancellable = false })

    configure_world()
    initialize_loaded_players()
end

local function shutdown()
    stop_all_bow_charges()
    clear_projectiles()
    for _, entry in ipairs(participants) do
        if entry.connected then
            mcs_player_set_armor_value(entry.name, 0)
        end
    end
    for name in pairs(observer_names) do
        mcs_player_show(name)
        mcs_player_set_allow_flying(name, false)
    end
    state = STATE_WAITING
    participants = {}
    participant_by_name = {}
    finish_ticks = 0
    returned_to_lobby = {}
    observer_names = {}
    tick_count = 0
    bow_charging = {}
    projectiles = {}
    held_item_display = {}
    if return_bed then return_bed.clear() end
    if waiting_countdown then waiting_countdown.reset() end
    return_bed = nil
    waiting_countdown = nil
end

return {
    name = "pvp",
    depends = { "economy", "proxy_transfer" },
    init = init,
    shutdown = shutdown,
}
