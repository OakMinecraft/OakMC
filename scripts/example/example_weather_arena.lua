-- Scenario: atmosphere controller for an arena or event world.
--
-- What it does:
-- - starts the server in clear weather
-- - lets players vote for rain or clear weather with chat commands
-- - applies the result immediately once enough votes are collected

local VOTES_REQUIRED = 2
local rain_votes = {}
local clear_votes = {}

local function table_count(values)
    local count = 0
    local _

    for _ in pairs(values) do
        count = count + 1
    end

    return count
end

local function clear_vote_state()
    rain_votes = {}
    clear_votes = {}
end

local function apply_clear_weather()
    mcs_world_update_weather(0.0, 0.0, false)
    mcs_chat_send_system_message_all_player("[Weather] The sky is clear.")
    clear_vote_state()
end

local function apply_rain_weather()
    mcs_world_update_weather(1.0, 0.0, true)
    mcs_chat_send_system_message_all_player("[Weather] Rain started.")
    clear_vote_state()
end

local function handle_weather_vote(event)
    local playername = event.playername or event.username
    local message = event.message

    if playername == nil or message == nil then
        return
    end

    if message == "!rain" then
        rain_votes[playername] = true
        clear_votes[playername] = nil
        mcs_chat_send_system_message_all_player("[Weather] Rain votes: " .. table_count(rain_votes) .. "/" .. VOTES_REQUIRED)
        if table_count(rain_votes) >= VOTES_REQUIRED then
            apply_rain_weather()
        end
    elseif message == "!clear" then
        clear_votes[playername] = true
        rain_votes[playername] = nil
        mcs_chat_send_system_message_all_player("[Weather] Clear votes: " .. table_count(clear_votes) .. "/" .. VOTES_REQUIRED)
        if table_count(clear_votes) >= VOTES_REQUIRED then
            apply_clear_weather()
        end
    end
end

local function init()
    apply_clear_weather()
    mcs_event_register(MCS_EVENT_PLAYER_CHAT, 100, handle_weather_vote)
end

local function shutdown()
    clear_vote_state()
end

return {
    name = "weather_arena",
    depends = {},
    init = init,
    shutdown = shutdown,
}
