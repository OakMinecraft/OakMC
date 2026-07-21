-- Generic event dispatcher and tick scheduler service.
--
-- Copy this file into plugins/ and add "oakmc_runtime" to a consumer
-- plugin's depends list. Consumers obtain the API from OAKMC_RUNTIME inside
-- their init() callback. Timer names are shared, so prefix them with the
-- consumer plugin name.

local handlers = {}
local host_events = {}
local timers = {}
local current_tick = 0
local next_handler_order = 0
local active = false
local runtime = {}

local function assert_active()
    assert(active, "oakmc_runtime is not initialized")
end

local function sorted_insert(event_handlers, handler)
    event_handlers[#event_handlers + 1] = handler
    table.sort(event_handlers, function(left, right)
        if left.priority == right.priority then
            return left.order < right.order
        end
        return left.priority > right.priority
    end)
end

function runtime.emit(event_type, event)
    assert_active()
    for _, handler in ipairs(handlers[event_type] or {}) do
        handler.callback(event)
        if event and event.cancelled then
            break
        end
    end
end

local function register_host_event(event_type)
    if event_type == MCS_EVENT_SERVER_TICK or host_events[event_type] then
        return
    end

    assert(mcs_event_register(event_type, 100, function(event)
        runtime.emit(event_type, event)
    end), "cannot register host event " .. tostring(event_type))
    host_events[event_type] = true
end

function runtime.on(event_type, priority, callback)
    assert_active()
    assert(type(event_type) == "number", "event_type must be numeric")
    assert(type(callback) == "function", "event callback is required")

    next_handler_order = next_handler_order + 1
    handlers[event_type] = handlers[event_type] or {}
    sorted_insert(handlers[event_type], {
        priority = priority or 0,
        order = next_handler_order,
        callback = callback,
    })
    register_host_event(event_type)
end

function runtime.now()
    assert_active()
    return current_tick
end

function runtime.after(name, delay_ticks, callback)
    assert_active()
    assert(type(name) == "string" and name ~= "", "timer name is required")
    assert(type(delay_ticks) == "number" and delay_ticks >= 1, "delay must be positive")
    assert(type(callback) == "function", "timer callback is required")
    timers[name] = {
        next_tick = current_tick + math.floor(delay_ticks),
        callback = callback,
    }
end

function runtime.every(name, interval_ticks, callback)
    assert(type(interval_ticks) == "number" and interval_ticks >= 1, "interval must be positive")
    runtime.after(name, interval_ticks, callback)
    timers[name].interval = math.floor(interval_ticks)
end

function runtime.cancel(name)
    assert_active()
    local existed = timers[name] ~= nil
    timers[name] = nil
    return existed
end

local function tick()
    current_tick = current_tick + 1
    local due = {}

    for name, timer in pairs(timers) do
        if current_tick >= timer.next_tick then
            due[#due + 1] = { name = name, timer = timer }
        end
    end
    table.sort(due, function(left, right)
        if left.timer.next_tick == right.timer.next_tick then
            return left.name < right.name
        end
        return left.timer.next_tick < right.timer.next_tick
    end)

    for _, entry in ipairs(due) do
        local timer = timers[entry.name]
        if timer == entry.timer then
            if timer.interval then
                timer.next_tick = current_tick + timer.interval
            else
                timers[entry.name] = nil
            end
            timer.callback(current_tick)
        end
    end
end

local function init()
    assert(rawget(_G, "OAKMC_RUNTIME") == nil, "OAKMC_RUNTIME is already provided")
    active = true
    _G.OAKMC_RUNTIME = runtime

    assert(mcs_event_register(MCS_EVENT_SERVER_TICK, 100, function(event)
        tick()
        runtime.emit(MCS_EVENT_SERVER_TICK, event)
    end, { cancellable = false }), "cannot register runtime tick handler")
    host_events[MCS_EVENT_SERVER_TICK] = true
end

local function shutdown()
    if rawget(_G, "OAKMC_RUNTIME") == runtime then
        _G.OAKMC_RUNTIME = nil
    end
    handlers = {}
    host_events = {}
    timers = {}
    current_tick = 0
    next_handler_order = 0
    active = false
end

return {
    name = "oakmc_runtime",
    depends = {},
    init = init,
    shutdown = shutdown,
}
