-- Velocity-aware /hub command for game servers.

local proxy_transfer = assert(dofile("plugins/proxy_transfer.lua"))

local HUB_SERVER_NAME = os.getenv("OAKMC_HUB_SERVER_NAME") or "lobby"
local HUB_HOST = os.getenv("OAKMC_HUB_HOST") or "127.0.0.1"
local HUB_PORT = tonumber(os.getenv("OAKMC_HUB_PORT") or "") or 10000

local function hub(context, args)
    if context.playername == nil then
        mcs_server_send_message("[hub] /hub can only be used by a player", MCS_LOG_WARN)
        return true
    end

    if #args > 0 then
        mcs_chat_send_system_message_to_player(context.playername, "Usage: /hub")
        return true
    end

    if not proxy_transfer.connect(
            context.playername,
            HUB_SERVER_NAME,
            HUB_HOST,
            HUB_PORT
        ) then
        mcs_chat_send_system_message_to_player(
            context.playername,
            "Unable to connect to the hub. Please try again."
        )
        return false
    end

    return true
end

local function init()
    assert(mcs_command_register(
        "hub",
        "hub",
        "Return to the hub",
        false,
        hub
    ))
end

return {
    name = "hub_command",
    depends = { "proxy_transfer" },
    init = init,
}
