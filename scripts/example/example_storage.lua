-- Generic namespaced persistent storage service.
--
-- Copy this file into plugins/ and add "oakmc_storage" to a consumer
-- plugin's depends list. Consumers obtain the API from OAKMC_STORAGE inside
-- their init() callback. Values must contain only serializable Lua data:
-- nil, booleans, finite numbers, strings, and acyclic tables using string or
-- number keys.

local persistence = require("plugins.common.persistence")
local table_utils = require("plugins.common.table")

local DATA_FILE = os.getenv("OAKMC_STORAGE_DATA_FILE") or "plugins/storage.data"
local namespaces = {}
local active = false
local storage = { data_file = DATA_FILE }

local function log(message, log_type)
    mcs_server_send_message("[storage] " .. message, log_type or MCS_LOG_INFO)
end

local store = persistence.new({
    data_file = DATA_FILE,
    lock_timeout_ms = 5000,
    log = log,
})

local function assert_active()
    assert(active, "oakmc_storage is not initialized")
end

local function assert_name(value, label)
    assert(type(value) == "string" and value ~= "", label .. " must be a non-empty string")
end

local function copy_serializable(value)
    if value == nil then return nil end
    local serializable, serialize_error = pcall(table_utils.serialize, value)
    if not serializable then error(serialize_error, 0) end
    return table_utils.copy(value)
end

local function load_data()
    local read_ok, loaded = store.read()
    if read_ok and loaded == nil then
        namespaces = {}
        return true
    end
    if not read_ok or type(loaded) ~= "table" or
        loaded.version ~= 1 or type(loaded.namespaces) ~= "table" then
        log("invalid storage data file: " .. DATA_FILE, MCS_LOG_ERROR)
        return false
    end
    local copy_ok, copied = pcall(copy_serializable, loaded.namespaces)
    if not copy_ok then
        log("invalid storage values: " .. tostring(copied), MCS_LOG_ERROR)
        return false
    end
    namespaces = copied
    return true
end

local function save_data()
    return store.write(function()
        return "-- OakMC generic storage; edit only while the server is stopped.\nreturn " ..
            table_utils.serialize({ version = 1, namespaces = namespaces }) .. "\n"
    end)
end

local function access(write, callback)
    assert_active()
    local lock_ok, result = store.with_lock(function()
        if not load_data() then
            return { ok = false, error = "load_failed" }
        end

        local callback_ok, value, extra = pcall(callback)
        if not callback_ok then
            return { ok = false, error = value }
        end
        if write and not save_data() then
            load_data()
            return { ok = false, error = "save_failed" }
        end
        return { ok = true, value = value, extra = extra }
    end)

    if not lock_ok or type(result) ~= "table" then
        return false, "lock_failed"
    end
    if not result.ok then
        return false, result.error
    end
    return true, result.value, result.extra
end

function storage.get(namespace, key, default)
    assert_name(namespace, "namespace")
    assert_name(key, "key")
    return access(false, function()
        local bucket = namespaces[namespace]
        local value = bucket and bucket[key]
        if value == nil then value = default end
        return table_utils.copy(value)
    end)
end

function storage.list(namespace)
    assert_name(namespace, "namespace")
    return access(false, function()
        return table_utils.copy(namespaces[namespace] or {})
    end)
end

function storage.set(namespace, key, value)
    assert_name(namespace, "namespace")
    assert_name(key, "key")
    assert(value ~= nil, "storage.set value cannot be nil; use storage.delete")
    return access(true, function()
        namespaces[namespace] = namespaces[namespace] or {}
        namespaces[namespace][key] = copy_serializable(value)
        return table_utils.copy(namespaces[namespace][key])
    end)
end

function storage.update(namespace, key, callback)
    assert_name(namespace, "namespace")
    assert_name(key, "key")
    assert(type(callback) == "function", "storage.update callback is required")
    return access(true, function()
        local bucket = namespaces[namespace]
        local current = bucket and bucket[key]
        local replacement = callback(table_utils.copy(current))

        namespaces[namespace] = namespaces[namespace] or {}
        namespaces[namespace][key] = copy_serializable(replacement)
        if next(namespaces[namespace]) == nil then
            namespaces[namespace] = nil
        end
        return table_utils.copy(replacement)
    end)
end

function storage.delete(namespace, key)
    assert_name(namespace, "namespace")
    assert_name(key, "key")
    return access(true, function()
        local bucket = namespaces[namespace]
        local existed = bucket ~= nil and bucket[key] ~= nil
        if bucket then
            bucket[key] = nil
            if next(bucket) == nil then namespaces[namespace] = nil end
        end
        return existed
    end)
end

function storage.reload()
    assert_active()
    local lock_ok, loaded = store.with_lock(load_data)
    return lock_ok and loaded == true
end

local function init()
    assert(rawget(_G, "OAKMC_STORAGE") == nil, "OAKMC_STORAGE is already provided")
    active = true
    assert(storage.reload(), "cannot load generic storage data")
    _G.OAKMC_STORAGE = storage
end

local function shutdown()
    if rawget(_G, "OAKMC_STORAGE") == storage then
        _G.OAKMC_STORAGE = nil
    end
    namespaces = {}
    active = false
end

return {
    name = "oakmc_storage",
    depends = {},
    init = init,
    shutdown = shutdown,
}
