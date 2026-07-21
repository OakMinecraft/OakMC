-- Shared short-lived game instance lifecycle plugin.
--
-- Instance-local wrappers set OAKMC_GAME_KEY, OAKMC_GAME_NAME and the signed
-- lobby callback command before loading this file.

local TICKS_PER_SECOND = 20
local DEFAULT_LIFETIME_SECONDS = 100
local DEFAULT_HEARTBEAT_SECONDS = 5
local LOBBY_TARGET_ID = os.getenv("OAKMC_LOBBY_REMOTE_ID") or "lobby"
local LOBBY_REMOTE_HOST = os.getenv("OAKMC_LOBBY_REMOTE_HOST") or "127.0.0.1"
local LOBBY_REMOTE_PORT = tonumber(os.getenv("OAKMC_LOBBY_REMOTE_PORT") or "") or 25575
local HEARTBEAT_COMMAND = os.getenv("OAKMC_GAME_HEARTBEAT_COMMAND") or "room-heartbeat"

local game_key = rawget(_G, "OAKMC_GAME_KEY") or os.getenv("OAKMC_GAME_KEY") or "tnt"
local game_name = rawget(_G, "OAKMC_GAME_NAME") or os.getenv("OAKMC_GAME_NAME") or "TNT 狂欢"
local closed_command = rawget(_G, "OAKMC_GAME_CLOSED_COMMAND") or
    os.getenv("OAKMC_GAME_CLOSED_COMMAND") or
    (game_key .. "-server-closed")

local lifetime_seconds = tonumber(
    rawget(_G, "OAKMC_GAME_LIFETIME_SECONDS") or
    os.getenv("OAKMC_GAME_LIFETIME_SECONDS") or
    ""
)
if lifetime_seconds == nil or lifetime_seconds <= 0 then
    lifetime_seconds = DEFAULT_LIFETIME_SECONDS
end
lifetime_seconds = math.max(1, math.floor(lifetime_seconds))

local heartbeat_seconds = tonumber(
    rawget(_G, "OAKMC_GAME_HEARTBEAT_SECONDS") or
    os.getenv("OAKMC_GAME_HEARTBEAT_SECONDS") or
    ""
) or DEFAULT_HEARTBEAT_SECONDS
heartbeat_seconds = math.max(1, math.floor(heartbeat_seconds))

local max_players = tonumber(
    rawget(_G, "OAKMC_GAME_MAX_PLAYERS") or
    os.getenv("OAKMC_GAME_MAX_PLAYERS") or
    ""
) or (game_key == "pvp" and 4 or 20)
max_players = math.max(1, math.floor(max_players))

local elapsed_ticks = 0
local heartbeat_ticks = 0
local shutdown_started = false
local had_players = false

local function json_escape(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
end

local function log(message, level)
    mcs_server_send_message("[" .. game_key .. "-lifecycle] " .. message, level or MCS_LOG_INFO)
end

local function notify_lobby(port, reason)
    local command = string.format("%s %d %s", closed_command, port, reason)
    local ok, response = mcs_remote_command_send(
        LOBBY_TARGET_ID,
        LOBBY_REMOTE_HOST,
        LOBBY_REMOTE_PORT,
        command
    )

    if ok then
        log(string.format("已通知 lobby：%s 服务器端口 %d 即将关闭", game_name, port))
        return true
    end

    log(
        string.format(
            "通知 lobby 失败（目标=%s@%s:%d，响应=%s）",
            LOBBY_TARGET_ID,
            LOBBY_REMOTE_HOST,
            LOBBY_REMOTE_PORT,
            response or "unavailable"
        ),
        MCS_LOG_ERROR
    )
    return false
end

local function send_heartbeat()
    local command = string.format(
        "%s %s %d %d %d",
        HEARTBEAT_COMMAND,
        game_key,
        mcs_server_get_port(),
        mcs_player_count(),
        max_players
    )
    local ok, response = mcs_remote_command_send(
        LOBBY_TARGET_ID,
        LOBBY_REMOTE_HOST,
        LOBBY_REMOTE_PORT,
        command
    )
    if not ok then
        log(string.format(
            "发送 lobby 心跳失败（目标=%s@%s:%d，响应=%s）",
            LOBBY_TARGET_ID,
            LOBBY_REMOTE_HOST,
            LOBBY_REMOTE_PORT,
            response or "unavailable"
        ), MCS_LOG_ERROR)
    end
    return ok
end

local function close_server(reason)
    if shutdown_started then
        return
    end
    shutdown_started = true

    local port = mcs_server_get_port()
    if reason == "empty" then
        log(string.format("房间人数已归零，准备删除端口 %d 的动态实例", port))
    else
        log(string.format("运行时间达到 %d 秒，准备删除端口 %d 的动态实例", lifetime_seconds, port))
        mcs_chat_send_system_message_all_player(
            string.format(
                '{"text":"%s 服务器运行时间已结束，服务器即将关闭。","color":"yellow","bold":true}',
                json_escape(game_name)
            )
        )
    end
    notify_lobby(port, reason)

    if not mcs_server_delete_current_instance() and not mcs_server_shutdown() then
        shutdown_started = false
        log("请求删除或关闭服务器失败，将在下一 tick 重试", MCS_LOG_ERROR)
    end
end

local function on_server_tick()
    if shutdown_started then
        return
    end

    local player_count = mcs_player_count()
    if player_count > 0 then
        had_players = true
    elseif had_players then
        close_server("empty")
        return
    end

    elapsed_ticks = elapsed_ticks + 1
    heartbeat_ticks = heartbeat_ticks + 1
    if heartbeat_ticks >= heartbeat_seconds * TICKS_PER_SECOND then
        heartbeat_ticks = 0
        send_heartbeat()
    end
    if elapsed_ticks >= lifetime_seconds * TICKS_PER_SECOND then
        close_server("timeout")
    end
end

local function init()
    elapsed_ticks = 0
    heartbeat_ticks = 0
    shutdown_started = false
    had_players = false
    mcs_event_register(MCS_EVENT_SERVER_TICK, 100, on_server_tick, { cancellable = false })
    log(string.format("插件已加载，%s 服务器将在 %d 秒后自动关闭", game_name, lifetime_seconds))
end

return {
    name = game_key .. "_lifecycle",
    depends = {},
    init = init,
}
