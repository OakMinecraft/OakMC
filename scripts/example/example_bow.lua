-- Basic server-authoritative bow implementation for protocol 775.
-- Supports charging, normal arrow ammo, projectile physics, solid-block
-- collision, player collision, damage, and entity cleanup. Durability,
-- enchantments, arrow pickup, and detailed block collision shapes are omitted.

-- OakMC's 26.1.2 item registry IDs. These are protocol registry IDs, not
-- stable IDs shared with other Minecraft/Pumpkin data revisions.
local BOW_ITEM_ID = 895
local ARROW_ITEM_ID = 896
local ARROW_ENTITY_TYPE_ID = 6

local MAIN_HAND = 0
local SURVIVAL = 0
local CREATIVE = 1
local ADVENTURE = 2
local SPECTATOR = 3

local MIN_CHARGE_TICKS = 3
local FULL_CHARGE_TICKS = 20
local MAX_PROJECTILE_TICKS = 200
local MAX_EMBEDDED_TICKS = 1200
local MAX_ACTIVE_PROJECTILES = 256
local GRAVITY_PER_TICK = 0.05
local AIR_DRAG = 0.99
local COLLISION_STEP = 0.2
local SHOOTER_GRACE_TICKS = 5
local PLAYER_RADIUS = 0.3
local PLAYER_HEIGHT = 1.8
local PLAYER_EYE_HEIGHT = 1.62

-- Set to true for vanilla-like survival ammo consumption. Keeping this false
-- makes the standalone script usable with only a bow in the current inventory.
local REQUIRE_ARROW_AMMO = false
local BOW_DEBUG_LOG = true

local tick_count = 0
local charging = {}
local projectiles = {}

local function bow_log(message, log_type)
    if BOW_DEBUG_LOG then
        mcs_server_send_message("[bow] " .. message, log_type or MCS_LOG_INFO)
    end
end

local function player_key(event)
    return event.username or event.playername
end

local function charge_power(charged_ticks)
    local t = charged_ticks / FULL_CHARGE_TICKS
    local power = (t * t + 2.0 * t) / 3.0

    if power > 1.0 then
        return 1.0
    end
    if power < 0.0 then
        return 0.0
    end
    return power
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
    -- Minecraft projectile rotations are derived directly from velocity.
    -- Negating these angles mirrors yaw and flips pitch, making the arrow
    -- model point away from its actual flight direction.
    local yaw = math.deg(math.atan(vx, vz))
    local pitch = math.deg(math.atan(vy, horizontal))
    return yaw, pitch
end

local function find_and_consume_arrow(player)
    if player.game_mode == CREATIVE then
        return true
    end
    if player.game_mode ~= SURVIVAL and player.game_mode ~= ADVENTURE then
        return false
    end

    for slot_id = 0, 35 do
        local slot = mcs_player_get_inventory_info(player.username, slot_id)

        if slot ~= nil and slot.used and slot.item_id == ARROW_ITEM_ID and slot.count > 0 then
            return mcs_player_set_inventory_item(
                player.username,
                slot_id,
                ARROW_ITEM_ID,
                slot.count - 1,
                nil
            )
        end
    end

    return false
end

local function segment_aabb_t(x0, y0, z0, x1, y1, z1, min_x, min_y, min_z, max_x, max_y, max_z)
    local t_min = 0.0
    local t_max = 1.0
    local starts = {x0, y0, z0}
    local deltas = {x1 - x0, y1 - y0, z1 - z0}
    local minimums = {min_x, min_y, min_z}
    local maximums = {max_x, max_y, max_z}

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
            if near_t > t_min then
                t_min = near_t
            end
            if far_t < t_max then
                t_max = far_t
            end
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
    local steps = math.max(1, math.ceil(distance / COLLISION_STEP))

    for step = 1, steps do
        local t = step / steps
        local x = x0 + dx * t
        local y = y0 + dy * t
        local z = z0 + dz * t

        if mcs_block_is_solid(math.floor(x), math.floor(y), math.floor(z)) then
            return t
        end
    end

    return nil
end

local function player_hit(projectile, x0, y0, z0, x1, y1, z1, players, block_t)
    local best_player = nil
    local best_t = block_t or math.huge

    for i = 1, #players do
        local player = players[i]
        local can_hit = player.play_initialized and player.game_mode == SURVIVAL and
            player.dimension_id == projectile.dimension_id and player.health > 0

        if can_hit and
            (player.entity_id ~= projectile.shooter_entity_id or projectile.age >= SHOOTER_GRACE_TICKS) then
            local hit_t = segment_aabb_t(
                x0,
                y0,
                z0,
                x1,
                y1,
                z1,
                player.x - PLAYER_RADIUS,
                player.y,
                player.z - PLAYER_RADIUS,
                player.x + PLAYER_RADIUS,
                player.y + PLAYER_HEIGHT,
                player.z + PLAYER_RADIUS
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

local function fire_arrow(player, power)
    if #projectiles >= MAX_ACTIVE_PROJECTILES then
        bow_log("active projectile limit reached", MCS_LOG_WARN)
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
        ARROW_ENTITY_TYPE_ID,
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

    if entity_id == nil then
        bow_log("mcs_entity_spawn failed for " .. player.username, MCS_LOG_ERROR)
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
    bow_log(string.format("spawned arrow entity=%d shooter=%s power=%.2f", entity_id, player.username, power))
    return true
end

local function on_use_item(event)
    local key = player_key(event)
    bow_log(string.format(
        "use item event player=%s hand=%s item_id=%s sequence=%s",
        tostring(key),
        tostring(event.hand),
        tostring(event.item_id),
        tostring(event.sequence)
    ))

    if event.hand ~= nil and event.hand ~= MAIN_HAND then
        bow_log("use item ignored for non-main hand: hand=" .. tostring(event.hand), MCS_LOG_WARN)
        return
    end
    if key == nil then
        bow_log("use item ignored because player identity is missing", MCS_LOG_WARN)
        return
    end

    local player = mcs_player_get_info_by_name(key)
    if player == nil or not player.play_initialized then
        bow_log("use item player is unavailable: " .. tostring(key), MCS_LOG_WARN)
        return
    end

    local held = mcs_player_get_inventory_info(player.username, player.selected_inventory_id)
    if held == nil or not held.used or held.item_id ~= BOW_ITEM_ID then
        bow_log(string.format(
            "use item ignored because selected item is not bow: event_item_id=%s selected_item_id=%s slot=%s",
            tostring(event.item_id),
            tostring(held ~= nil and held.item_id or nil),
            tostring(player.selected_inventory_id)
        ), MCS_LOG_WARN)
        return
    end

    if charging[key] ~= nil then
        return
    end

    charging[key] = {start_tick = tick_count}
    bow_log("started charging for " .. key)
end

local function on_release_use_item(event)
    local key = player_key(event)
    local charge = key ~= nil and charging[key] or nil

    if key ~= nil then
        charging[key] = nil
    end
    if charge == nil then
        bow_log("release ignored because no charge state exists for " .. tostring(key), MCS_LOG_WARN)
        return
    end
    if event.item_id ~= BOW_ITEM_ID then
        bow_log("release item is not bow: item_id=" .. tostring(event.item_id), MCS_LOG_WARN)
        return
    end

    local player = mcs_player_get_info_by_name(key)
    if player == nil or not player.play_initialized then
        bow_log("release player is unavailable: " .. tostring(key), MCS_LOG_WARN)
        return
    end

    local held = mcs_player_get_inventory_info(player.username, player.selected_inventory_id)
    if held == nil or not held.used or held.item_id ~= BOW_ITEM_ID then
        bow_log("selected slot no longer contains bow for " .. player.username, MCS_LOG_WARN)
        return
    end

    local charged_ticks = tick_count - charge.start_tick
    if charged_ticks < MIN_CHARGE_TICKS then
        bow_log("charge was too short: ticks=" .. tostring(charged_ticks), MCS_LOG_WARN)
        return
    end

    local power = charge_power(charged_ticks)
    if power < 0.1 then
        bow_log("charge power was too low", MCS_LOG_WARN)
        return
    end

    if REQUIRE_ARROW_AMMO and not find_and_consume_arrow(player) then
        bow_log(string.format("no arrow item (id %d) found for %s", ARROW_ITEM_ID, player.username), MCS_LOG_WARN)
        return
    end

    fire_arrow(player, power)
end

local function on_player_quit(event)
    local key = player_key(event)
    if key ~= nil then
        charging[key] = nil
    end
end

local function update_flying_projectile(index, projectile, players)
    local old_x = projectile.x
    local old_y = projectile.y
    local old_z = projectile.z
    local new_x = old_x + projectile.vx
    local new_y = old_y + projectile.vy
    local new_z = old_z + projectile.vz
    local block_t = solid_block_hit_t(old_x, old_y, old_z, new_x, new_y, new_z)
    local target = player_hit(projectile, old_x, old_y, old_z, new_x, new_y, new_z, players, block_t)

    projectile.age = projectile.age + 1

    if target ~= nil then
        local speed = math.sqrt(
            projectile.vx * projectile.vx +
            projectile.vy * projectile.vy +
            projectile.vz * projectile.vz
        )
        local damage = math.max(1, math.ceil(speed * 2.0))

        if projectile.critical then
            damage = damage + math.random(0, math.floor(damage / 2) + 1)
        end

        mcs_player_apply_damage(target.username, projectile.shooter_entity_id, damage, 0)
        bow_log(string.format(
            "arrow entity=%d hit player=%s speed=%.3f critical=%s damage=%d",
            projectile.entity_id,
            target.username,
            speed,
            tostring(projectile.critical),
            damage
        ))
        remove_projectile(index)
    elseif block_t ~= nil then
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
        else
            bow_log(string.format(
                "arrow entity=%d embedded at x=%.2f y=%.2f z=%.2f",
                projectile.entity_id,
                hit_x,
                hit_y,
                hit_z
            ))
        end
    elseif projectile.age >= MAX_PROJECTILE_TICKS or new_y < -80.0 or new_y > 400.0 then
        remove_projectile(index)
    else
        projectile.x = new_x
        projectile.y = new_y
        projectile.z = new_z
        projectile.vx = projectile.vx * AIR_DRAG
        projectile.vy = projectile.vy * AIR_DRAG - GRAVITY_PER_TICK
        projectile.vz = projectile.vz * AIR_DRAG

        -- The client advances arrow entities locally from their initial
        -- velocity using the same drag and gravity. Sending an absolute
        -- position every server tick fights that simulation and causes
        -- visible rubber-banding. The server keeps its own trajectory
        -- here solely for authoritative collision and cleanup.
    end
end

local function update_projectiles()
    tick_count = tick_count + 1

    local players = mcs_player_list_info() or {}

    for index = #projectiles, 1, -1 do
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
end

local function init()
    mcs_event_register(MCS_EVENT_USE_ITEM, 100, on_use_item)
    mcs_event_register(MCS_EVENT_RELEASE_USE_ITEM, 100, on_release_use_item)
    mcs_event_register(MCS_EVENT_PLAYER_QUIT, 100, on_player_quit)
    mcs_event_register(MCS_EVENT_SERVER_TICK, 50, update_projectiles, {cancellable = false})
    bow_log(string.format(
        "script loaded; bow=%d arrow=%d entity_type=%d require_ammo=%s",
        BOW_ITEM_ID,
        ARROW_ITEM_ID,
        ARROW_ENTITY_TYPE_ID,
        tostring(REQUIRE_ARROW_AMMO)
    ))
end

local function shutdown()
    for index = #projectiles, 1, -1 do
        mcs_entity_remove(projectiles[index].entity_id)
        table.remove(projectiles, index)
    end
    charging = {}
    bow_log("plugin unloaded")
end

return {
    name = "bow",
    depends = {},
    init = init,
    shutdown = shutdown,
}
