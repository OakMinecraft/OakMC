-- Scenario: join welcome.
--
-- What it does:
-- - greets each player when they join
-- - shows a title/subtitle
-- - sets a shared default spawn point when the server starts
--
-- To try it, copy this file into plugins/ and run reload-lua.

local SPAWN_X = 100
local SPAWN_Y = 128
local SPAWN_Z = 0

local function welcome_player(event)
    local playername = event.playername or event.username

    if playername == nil then
        return
    end

    mcs_chat_send_system_message_all_player("[OakMC] " .. playername .. " joined the server.")
    mcs_title_set_time(playername, 10, 70, 20)
    mcs_title_set_text(playername, "Welcome to OakMC")
    mcs_title_set_subtitle_text(playername, "Minecraft 26.1.2 / protocol 775")
    mcs_player_play_sound_name(playername, "minecraft:entity.player.levelup", 0, 1.0, 1.0, 0)
end

local function configure_spawn(event)
    mcs_world_set_default_spawn_position("minecraft:overworld", SPAWN_X, SPAWN_Y, SPAWN_Z, 0, 0)
    mcs_chat_send_system_message_all_player("[OakMC] Welcome example loaded.")
end

local function init()
    mcs_event_register(MCS_EVENT_SERVER_START, 100, configure_spawn)
    mcs_event_register(MCS_EVENT_PLAYER_JOIN, 100, welcome_player)
end

return {
    name = "welcome",
    depends = {},
    init = init,
}
