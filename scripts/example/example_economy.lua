-- Persistent integer economy for OakMC.
--
-- Player commands are chat commands because Lua plugins do not currently add
-- entries to the vanilla command tree. Commands are private and are consumed
-- before the normal chat broadcaster sees them:
--   !money / !balance [player]
--   !pay <player> <amount>
--   !baltop
--   Daily check-in is granted automatically when a player joins.
--   !eco <give|take|set|reload|save> ... (OP only)

local DATA_FILE = os.getenv("OAKMC_ECONOMY_DATA_FILE") or "plugins/economy.data"
local LOCK_FILE = DATA_FILE .. ".lock"
local LOCK_TIMEOUT_MS = 5000
local STARTING_BALANCE = 1000
local MAX_BALANCE = 9000000000000000
local MAX_TRANSACTION = 1000000000000000
local TOP_LIMIT = 10
local DAILY_REWARD = 100

local accounts = {}
local private_delivery = nil
local data_lock_depth = 0

local function log(message, log_type)
    mcs_server_send_message("[economy] " .. message, log_type or MCS_LOG_INFO)
end

local function is_integer(value)
    return type(value) == "number" and value >= 0 and value <= MAX_BALANCE and
        value == math.floor(value)
end

local function format_money(value)
    local text = tostring(math.floor(value))
    local changed

    repeat
        text, changed = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
    until changed == 0

    return text
end

local function parse_amount(value, allow_zero)
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil
    end

    local amount = tonumber(value)
    if amount == nil or amount > MAX_TRANSACTION or amount ~= math.floor(amount) then
        return nil
    end
    if not allow_zero and amount == 0 then
        return nil
    end
    return amount
end

local function sorted_account_ids()
    local ids = {}
    for uuid in pairs(accounts) do
        ids[#ids + 1] = uuid
    end
    table.sort(ids)
    return ids
end

local function serialize_data()
    local lines = {
        "-- OakMC economy data; edit only while the server is stopped.",
        "return {",
        "    version = 2,",
        "    accounts = {",
    }

    for _, uuid in ipairs(sorted_account_ids()) do
        local account = accounts[uuid]
        lines[#lines + 1] = string.format(
            "        [%q] = { balance = %d, name = %q, updated_at = %d, last_daily = %q },",
            uuid,
            account.balance,
            account.name,
            account.updated_at or 0,
            account.last_daily or ""
        )
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

local function save_data()
    local temporary = DATA_FILE .. ".tmp"
    local file, err = io.open(temporary, "w")
    if file == nil then
        log("cannot open temporary data file: " .. tostring(err), MCS_LOG_ERROR)
        return false
    end

    local write_ok, write_err = file:write(serialize_data())
    if not write_ok then
        log("cannot write temporary data file: " .. tostring(write_err), MCS_LOG_ERROR)
        file:close()
        os.remove(temporary)
        return false
    end
    local flush_ok, flush_err = file:flush()
    if not flush_ok then
        log("cannot flush temporary data file: " .. tostring(flush_err), MCS_LOG_ERROR)
        file:close()
        os.remove(temporary)
        return false
    end
    local close_ok, close_err = file:close()
    if not close_ok then
        log("cannot close temporary data file: " .. tostring(close_err), MCS_LOG_ERROR)
        os.remove(temporary)
        return false
    end

    if os.rename(temporary, DATA_FILE) then
        return true
    end

    -- Windows does not replace an existing file with rename(). Keep the
    -- atomic path as the first choice, then use a replacement fallback.
    os.remove(DATA_FILE)
    if os.rename(temporary, DATA_FILE) then
        return true
    end

    log("cannot replace data file", MCS_LOG_ERROR)
    os.remove(temporary)
    return false
end

local function valid_loaded_account(uuid, account)
    return type(uuid) == "string" and uuid ~= "" and type(account) == "table" and
        is_integer(account.balance) and type(account.name) == "string" and account.name ~= "" and
        (account.last_daily == nil or type(account.last_daily) == "string")
end

local function load_data()
    local file = io.open(DATA_FILE, "r")
    if file == nil then
        accounts = {}
        return true
    end
    file:close()

    local ok, loaded = pcall(dofile, DATA_FILE)
    if not ok or type(loaded) ~= "table" or type(loaded.accounts) ~= "table" then
        local backup = DATA_FILE .. ".corrupt." .. tostring(os.time())
        os.rename(DATA_FILE, backup)
        accounts = {}
        log("invalid data file; moved it to " .. backup, MCS_LOG_ERROR)
        return false
    end

    accounts = {}
    local ignored = 0
    for uuid, account in pairs(loaded.accounts) do
        if valid_loaded_account(uuid, account) then
            accounts[uuid] = {
                balance = account.balance,
                name = account.name,
                updated_at = is_integer(account.updated_at) and account.updated_at or 0,
                last_daily = account.last_daily or "",
            }
        else
            ignored = ignored + 1
        end
    end

    if ignored > 0 then
        log("ignored " .. tostring(ignored) .. " malformed account(s)", MCS_LOG_WARN)
    end
    return true
end

local function with_latest_data(callback)
    if data_lock_depth > 0 then
        local ok, result = pcall(callback)
        if not ok then
            log("shared data operation failed: " .. tostring(result), MCS_LOG_ERROR)
        end
        return ok, result
    end

    local lock_id = mcs_server_file_lock(LOCK_FILE, LOCK_TIMEOUT_MS)
    if lock_id == nil then
        log("timed out waiting for shared data lock: " .. LOCK_FILE, MCS_LOG_ERROR)
        return false
    end

    data_lock_depth = 1
    local load_ok = load_data()
    local call_ok, result = pcall(callback)
    data_lock_depth = 0
    local unlock_ok = mcs_server_file_unlock(lock_id)

    if not call_ok then
        log("shared data operation failed: " .. tostring(result), MCS_LOG_ERROR)
    end
    if not unlock_ok then
        log("cannot release shared data lock: " .. LOCK_FILE, MCS_LOG_ERROR)
    end
    return load_ok and call_ok and unlock_ok, result
end


local function player_info(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return mcs_player_get_info_by_name(name)
end

local function ensure_account(info)
    if info == nil or type(info.uuid) ~= "string" or info.uuid == "" then
        return nil, false
    end

    local account = accounts[info.uuid]
    if account == nil then
        account = {
            balance = STARTING_BALANCE,
            name = info.username,
            updated_at = os.time(),
            last_daily = "",
        }
        accounts[info.uuid] = account
        return account, true
    end

    if type(info.username) == "string" and info.username ~= "" and account.name ~= info.username then
        account.name = info.username
        account.updated_at = os.time()
        return account, true
    end
    return account, false
end

local function find_account_by_name(name)
    local wanted = string.lower(name)
    local online = mcs_player_list_info() or {}

    for _, info in ipairs(online) do
        if info.username ~= nil and string.lower(info.username) == wanted then
            local account, changed = ensure_account(info)
            if changed then
                save_data()
            end
            return info.uuid, account, info.username
        end
    end

    for uuid, account in pairs(accounts) do
        if string.lower(account.name) == wanted then
            return uuid, account, account.name
        end
    end
    return nil
end

local function tell(name, message)
    local direct_send = rawget(_G, "mcs_chat_send_system_message_to_player")
    if type(direct_send) == "function" and direct_send(name, message) then
        return
    end

    private_delivery = {name = name, message = message}
    local ok = mcs_chat_send_system_message_all_player(message)
    private_delivery = nil
    if not ok then
        mcs_title_set_action_bar_text(name, message)
    end
end

local function refresh_sidebar(name)
    local refresh = rawget(_G, "oakmc_lobby_refresh_scoreboard")
    if type(refresh) ~= "function" then
        return
    end

    local ok, err = pcall(refresh, name)
    if not ok then
        log("cannot refresh sidebar for " .. tostring(name) .. ": " .. tostring(err), MCS_LOG_WARN)
    end
end

local function refresh_online_sidebars()
    for _, info in ipairs(mcs_player_list_info() or {}) do
        if info.username ~= nil and info.play_initialized then
            refresh_sidebar(info.username)
        end
    end
end

local function current_daily_key()
    return os.date("!%Y-%m-%d")
end

local function send_help(name)
    tell(name, "[经济] !money [玩家] | !pay <玩家> <金额> | !baltop")
    tell(name, "[经济] 每日登录自动签到，可得 " .. format_money(DAILY_REWARD) .. " 金币")
    tell(name, "[经济] OP: !eco <give|take|set> <玩家> <金额>，!eco save，!eco reload")
end

local function on_system_chat(event)
    if private_delivery == nil or event.message ~= private_delivery.message then
        return
    end
    if event.username ~= private_delivery.name and event.playername ~= private_delivery.name then
        event.cancelled = true
    end
end

local function command_tokens(message)
    local tokens = {}
    for token in message:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    return tokens
end

local function is_op(name)
    local info = player_info(name)
    return info ~= nil and info.is_op == true
end

local function on_balance(name, target_name)
    local target = target_name or name
    local uuid, account, canonical = find_account_by_name(target)
    if uuid == nil or account == nil then
        tell(name, "[经济] 找不到玩家账户: " .. target)
        return
    end
    tell(name, string.format("[经济] %s 的余额: %s", canonical, format_money(account.balance)))
end

local function on_pay(name, target_name, amount_text)
    local amount = parse_amount(amount_text, false)
    if amount == nil then
        tell(name, "[经济] 金额必须是 1 到 " .. tostring(MAX_TRANSACTION) .. " 的整数")
        return
    end

    local sender_info = player_info(name)
    local sender, sender_changed = ensure_account(sender_info)
    if sender == nil then
        tell(name, "[经济] 无法读取你的 UUID，请稍后再试")
        return
    end
    if sender_changed then
        save_data()
    end

    local target_uuid, target, canonical = find_account_by_name(target_name)
    if target_uuid == nil or target == nil then
        tell(name, "[经济] 找不到玩家账户: " .. tostring(target_name))
        return
    end
    if target_uuid == sender_info.uuid then
        tell(name, "[经济] 不能给自己转账")
        return
    end
    if sender.balance < amount then
        tell(name, "[经济] 余额不足，需要 " .. format_money(amount) .. "，当前 " .. format_money(sender.balance))
        return
    end
    if target.balance > MAX_BALANCE - amount then
        tell(name, "[经济] 对方余额已达到上限")
        return
    end

    sender.balance = sender.balance - amount
    target.balance = target.balance + amount
    sender.updated_at = os.time()
    target.updated_at = sender.updated_at

    if not save_data() then
        sender.balance = sender.balance + amount
        target.balance = target.balance - amount
        tell(name, "[经济] 数据保存失败，转账已取消")
        return
    end
    refresh_sidebar(name)
    refresh_sidebar(canonical)
    tell(name, string.format("[经济] 已向 %s 转账 %s，余额 %s", canonical, format_money(amount), format_money(sender.balance)))
end

local function claim_daily_reward(name)
    local info = player_info(name)
    local account = ensure_account(info)
    if account == nil then
        tell(name, "[经济] 无法读取你的 UUID，请稍后再试")
        return
    end

    local today = current_daily_key()
    if account.last_daily == today then
        tell(name, "[签到] 今天已经签过到了，明天再来吧")
        return
    end
    if account.balance > MAX_BALANCE - DAILY_REWARD then
        tell(name, "[签到] 余额已达到上限，暂时无法领取奖励")
        return
    end

    local old_balance = account.balance
    local old_last_daily = account.last_daily
    account.balance = account.balance + DAILY_REWARD
    account.last_daily = today
    account.updated_at = os.time()

    if not save_data() then
        account.balance = old_balance
        account.last_daily = old_last_daily
        tell(name, "[签到] 数据保存失败，本次签到未生效")
        return
    end

    refresh_sidebar(name)
    tell(name, string.format(
        "[签到] 登录签到成功，获得 %s 金币，当前余额 %s",
        format_money(DAILY_REWARD),
        format_money(account.balance)
    ))
end

local function on_join(event)
    local name = event.playername or event.username
    if not with_latest_data(function()
        local info = player_info(name)
        local _, changed = ensure_account(info)
        if changed then
            save_data()
        end
        claim_daily_reward(name)
    end) then
        log("cannot synchronize account or grant daily reward for " .. tostring(name), MCS_LOG_WARN)
    end
end

local function on_initialized(event)
    local name = event.playername or event.username
    if not with_latest_data(function()
        local info = player_info(name)
        local _, changed = ensure_account(info)
        if changed then
            save_data()
        end
    end) then
        log("cannot synchronize account for " .. tostring(name), MCS_LOG_WARN)
    end
end

local function on_top(name)
    local ids = sorted_account_ids()
    table.sort(ids, function(left, right)
        if accounts[left].balance == accounts[right].balance then
            return accounts[left].name < accounts[right].name
        end
        return accounts[left].balance > accounts[right].balance
    end)

    tell(name, "[经济] 余额排行榜")
    for index = 1, math.min(TOP_LIMIT, #ids) do
        local account = accounts[ids[index]]
        tell(name, string.format("[经济] #%d %s: %s", index, account.name, format_money(account.balance)))
    end
end

local function on_admin(name, tokens)
    if not is_op(name) then
        tell(name, "[经济] 只有 OP 可以使用管理命令")
        return
    end

    local action = string.lower(tokens[2] or "")
    if action == "save" then
        tell(name, save_data() and "[经济] 数据已保存" or "[经济] 数据保存失败")
        return
    end
    if action == "reload" then
        local ok = load_data()
        if ok then
            refresh_online_sidebars()
        end
        tell(name, ok and "[经济] 数据已重新载入" or "[经济] 数据文件有错误，已启用空账户表")
        return
    end
    if action ~= "give" and action ~= "take" and action ~= "set" then
        send_help(name)
        return
    end

    local amount = parse_amount(tokens[4], action == "set")
    if amount == nil then
        tell(name, "[经济] 金额必须是整数；give/take 大于 0，set 可为 0")
        return
    end
    local uuid, account, canonical = find_account_by_name(tokens[3] or "")
    if uuid == nil or account == nil then
        tell(name, "[经济] 找不到玩家账户: " .. tostring(tokens[3]))
        return
    end

    local old_balance = account.balance
    if action == "give" then
        if account.balance > MAX_BALANCE - amount then
            tell(name, "[经济] 操作会超过余额上限")
            return
        end
        account.balance = account.balance + amount
    elseif action == "take" then
        if account.balance < amount then
            tell(name, "[经济] 目标余额不足")
            return
        end
        account.balance = account.balance - amount
    else
        account.balance = amount
    end
    account.updated_at = os.time()

    if not save_data() then
        account.balance = old_balance
        tell(name, "[经济] 数据保存失败，操作已取消")
        return
    end
    refresh_sidebar(canonical)
    tell(name, string.format("[经济] %s 余额已更新为 %s", canonical, format_money(account.balance)))
end

local function on_chat(event)
    local name = event.playername or event.username
    local message = event.message
    if name == nil or type(message) ~= "string" or message:sub(1, 1) ~= "!" then
        return
    end

    local tokens = command_tokens(message)
    local command = string.lower(tokens[1] or "")
    if command ~= "!money" and command ~= "!balance" and command ~= "!bal" and
        command ~= "!pay" and command ~= "!baltop" and command ~= "!eco" then
        return
    end

    event.cancelled = true
    local synchronized = with_latest_data(function()
        if command == "!money" or command == "!balance" or command == "!bal" then
            if string.lower(tokens[2] or "") == "help" then
                send_help(name)
            else
                on_balance(name, tokens[2])
            end
        elseif command == "!pay" then
            if tokens[2] == nil or tokens[3] == nil then
                send_help(name)
            else
                on_pay(name, tokens[2], tokens[3])
            end
        elseif command == "!baltop" then
            on_top(name)
        else
            on_admin(name, tokens)
        end
    end)
    if not synchronized then
        tell(name, "[经济] 共享金额数据暂时不可用，请稍后重试")
    end
end

local function initialize_loaded_players()
    local changed = false
    for _, info in ipairs(mcs_player_list_info() or {}) do
        local _, account_changed = ensure_account(info)
        changed = changed or account_changed
    end
    if changed then
        save_data()
    end
end

local function init()
    _G.oakmc_economy_get_balance = function(name)
        local ok, balance = with_latest_data(function()
            local _, account = find_account_by_name(name)
            return account ~= nil and account.balance or nil
        end)
        return ok and balance or nil
    end
    _G.oakmc_economy_transaction = function(name, delta, required_balance)
        if type(delta) ~= "number" or delta ~= math.floor(delta) or
            math.abs(delta) > MAX_TRANSACTION then
            return false, "invalid_amount"
        end

        required_balance = required_balance or math.max(0, -delta)
        if type(required_balance) ~= "number" or required_balance < 0 or
            required_balance ~= math.floor(required_balance) or
            required_balance > MAX_TRANSACTION then
            return false, "invalid_amount"
        end

        local ok, result = with_latest_data(function()
            local info = player_info(name)
            local account = ensure_account(info)
            if account == nil then
                return { success = false, reason = "account_unavailable" }
            end
            if account.balance < required_balance then
                return {
                    success = false,
                    reason = "insufficient_funds",
                    balance = account.balance,
                }
            end

            local new_balance = account.balance + delta
            if new_balance < 0 then
                return {
                    success = false,
                    reason = "insufficient_funds",
                    balance = account.balance,
                }
            end
            if new_balance > MAX_BALANCE then
                return {
                    success = false,
                    reason = "balance_limit",
                    balance = account.balance,
                }
            end

            local old_balance = account.balance
            account.balance = new_balance
            account.updated_at = os.time()
            if not save_data() then
                account.balance = old_balance
                return {
                    success = false,
                    reason = "save_failed",
                    balance = old_balance,
                }
            end

            return { success = true, balance = new_balance }
        end)

        if not ok or type(result) ~= "table" then
            return false, "storage_unavailable"
        end
        if not result.success then
            return false, result.reason, result.balance
        end

        refresh_sidebar(name)
        return true, result.balance
    end
    mcs_event_register(MCS_EVENT_SYSTEM_CHAT, 1000, on_system_chat)
    mcs_event_register(MCS_EVENT_PLAYER_CHAT, 1000, on_chat)
    mcs_event_register(MCS_EVENT_PLAYER_JOIN, 1000, on_join)
    mcs_event_register(MCS_EVENT_PLAYER_INITIALIZED, 1000, on_initialized)
    if not with_latest_data(initialize_loaded_players) then
        log("cannot initialize shared economy data", MCS_LOG_ERROR)
    end
end

local function shutdown()
    _G.oakmc_economy_get_balance = nil
    _G.oakmc_economy_transaction = nil
    accounts = {}
    private_delivery = nil
    data_lock_depth = 0
end

return {
    name = "economy",
    depends = {},
    init = init,
    shutdown = shutdown,
}
