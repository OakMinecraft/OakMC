local function luahello(context, args)
    local message = #args > 0 and table.concat(args, " ") or "Hello from Lua"

    if context.playername ~= nil then
        mcs_title_set_action_bar_text(context.playername, message)
    else
        mcs_server_send_message(message, MCS_LOG_INFO)
    end
    return true
end

local function init()
    assert(mcs_command_register(
        "luahello",
        "luahello [message]",
        "Show a Lua-provided greeting",
        false,
        luahello
    ))
end

return {
    name = "command_example",
    depends = {},
    init = init,
}
