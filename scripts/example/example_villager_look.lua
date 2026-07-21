-- Villager look-at example.
-- Spawns one villager and makes it turn its head/body toward nearby players.

local VILLAGER_ENTITY_TYPE_ID = 139

local VILLAGER_X = 100.5
local VILLAGER_Y = 128.0
local VILLAGER_Z = 4.5

local LOOK_RADIUS = 8.0
local UPDATE_EVERY_TICKS = 4
local TURN_BODY = true

local villager_entity_id = nil
local tick_counter = 0
local last_yaw = 0.0

local function yaw_to_face(from_x, from_z, to_x, to_z)
    local dx = to_x - from_x
    local dz = to_z - from_z

    -- Minecraft yaw: 0 faces south (+Z), 90 faces west (-X).
    return -math.deg(math.atan(dx, dz))
end

local function nearest_player()
    local players = mcs_player_list_info()
    local best = nil
    local best_distance_sq = LOOK_RADIUS * LOOK_RADIUS

    if players == nil then
        return nil
    end

    for i = 1, #players do
        local player = players[i]
        local dx = player.x - VILLAGER_X
        local dz = player.z - VILLAGER_Z
        local distance_sq = dx * dx + dz * dz

        if player.play_initialized and distance_sq <= best_distance_sq then
            best = player
            best_distance_sq = distance_sq
        end
    end

    return best
end

local function spawn_villager()
    villager_entity_id = mcs_entity_spawn(
        VILLAGER_ENTITY_TYPE_ID,
        VILLAGER_X,
        VILLAGER_Y,
        VILLAGER_Z,
        last_yaw,
        0.0,
        last_yaw,
        0
    )

    if villager_entity_id ~= nil then
        mcs_chat_send_system_message_all_player(
            string.format("[OakMC] spawned look-at villager entity=%d", villager_entity_id)
        )
    end
end

local function update_villager_look()
    if villager_entity_id == nil then
        return
    end

    tick_counter = tick_counter + 1
    if tick_counter % UPDATE_EVERY_TICKS ~= 0 then
        return
    end

    local player = nearest_player()
    if player == nil then
        return
    end

    local head_yaw = yaw_to_face(VILLAGER_X, VILLAGER_Z, player.x, player.z)
    local body_yaw = last_yaw

    if TURN_BODY then
        body_yaw = head_yaw
        last_yaw = body_yaw
    end

    mcs_entity_rotate(
        villager_entity_id,
        VILLAGER_X,
        VILLAGER_Y,
        VILLAGER_Z,
        body_yaw,
        0.0,
        head_yaw
    )
end

local function init()
    mcs_event_register(MCS_EVENT_SERVER_START, 100, spawn_villager)
    mcs_event_register(MCS_EVENT_SERVER_TICK, 50, update_villager_look)
end

local function shutdown()
    if villager_entity_id ~= nil then
        mcs_entity_remove(villager_entity_id)
        villager_entity_id = nil
    end
end

return {
    name = "villager_look",
    depends = {},
    init = init,
    shutdown = shutdown,
}
