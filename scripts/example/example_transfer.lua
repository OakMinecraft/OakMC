-- Scenario: transfer players to another server.
--
-- What it does:
-- - listens for chat commands
-- - transfers a player to the configured server when they type !hub or !lobby
--
-- Notes:
-- - the current Lua chat event is observational, so the command may still appear
--   in normal chat depending on the server's default chat handler.
-- - replace HUB_HOST / HUB_PORT with your real target server.

local HUB_HOST = "127.0.0.1"
local HUB_PORT = 25566

local function transfer_to_hub(event)
    local playername = event.playername or event.username
    local message = event.message

    if playername == nil or message == nil then
        return
    end

    if message == "!hub" or message == "!lobby" then
        mcs_chat_send_system_message_all_player("[OakMC] Sending " .. playername .. " to the lobby.")
        mcs_player_transfer(playername, HUB_HOST, HUB_PORT)
    end
end

local function init()
    mcs_event_register(MCS_EVENT_PLAYER_CHAT, 100, transfer_to_hub)
end

return {
    name = "transfer",
    depends = {},
    init = init,
}
