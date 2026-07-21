# OakMC Lua Examples

Each file is a plugin module demonstrating one runtime scenario. To enable an
example, copy it into `plugins/` and run `reload-lua`.

Every example returns a module table with `name`, `depends`, `init`, and an
optional `shutdown`. Use `depends = {}` for an independent plugin, or list all
required plugin names, for example `depends = {"core", "economy"}`. OakMC
collects and validates every dependency before calling any `init()`.

Available examples:

- `example_runtime.lua`: dependency-friendly `OAKMC_RUNTIME` service with
  priority-ordered event dispatch and named one-shot/periodic tick timers
- `example_storage.lua`: dependency-friendly `OAKMC_STORAGE` service with
  namespaced, lock-protected, atomically replaced persistent Lua data
- `example_welcome.lua`: join welcome, title, subtitle, sound, default spawn
- `example_transfer.lua`: chat-triggered transfer to another server
- `example_hub_command.lua`: Velocity-aware `/hub` command that requests an internal switch to the fixed `lobby` backend at `127.0.0.1:10000`
- `plugins/proxy_transfer.lua`: optional `oakmc:proxy_transfer` bridge encoder for proxy-internal dynamic server switching
- `example_command.lua`: native server-command registration from Lua
- `example_weather_arena.lua`: weather voting for event worlds
- `example_pvp.lua`: last-player-standing PvP room with a two-player 15-second countdown, immediate four-player start, assigned spawns, server-authoritative attack cooldown, critical hits, hurt resistance, vanilla-style food regeneration, armor HUD attributes, melee/arrow/snowball velocity knockback, healing and Speed II potions, spectator mode, lobby-return bed, winner reward, and delayed return
- `example_bow.lua`: server-authoritative bow charging, arrow physics, wall embedding, and survival-player damage
- `example_villager_look.lua`: spawn one villager entity and rotate it toward nearby players
- `example_economy.lua`: UUID-keyed persistent balances, automatic login check-in rewards, private chat commands, transfers, leaderboard, and OP administration

Console commands and focused BossBar, GUI, component, and player-name snippets
are documented in `docs/command-examples.md`. Server startup, signed remote
commands, and isolated child instances are documented in
`docs/server-operations.md`.

The command examples also demonstrate the current component input rules:
titles, BossBar/GUI titles, and entity names accept plain text or JSON Text
Components, while item `nbt_data` currently maps only to
`minecraft:custom_name` rather than arbitrary raw NBT.

The examples target the current maintained runtime: Minecraft `26.1.2` /
protocol `775`.

## Reusable runtime and storage services

Copy `example_runtime.lua` and/or `example_storage.lua` into `plugins/`, keeping
their plugin names `oakmc_runtime` and `oakmc_storage`. A consumer declares the
service dependency and reads the global API inside `init()` (dependency order
does not apply while plugin files are only being collected):

```lua
local function init()
    local runtime = assert(OAKMC_RUNTIME)
    local storage = assert(OAKMC_STORAGE)

    runtime.on(MCS_EVENT_PLAYER_JOIN, 100, function(event)
        local name = event.playername or event.username
        if not name then return end

        local info = mcs_player_get_info_by_name(name)
        if not info then return end
        assert(storage.update("profiles", info.uuid, function(profile)
            profile = profile or { name = name, joins = 0 }
            profile.name = name
            profile.joins = profile.joins + 1
            return profile
        end))
    end)

    runtime.every("join_counter.save_notice", 1200, function()
        mcs_server_send_message("join-counter storage is active", MCS_LOG_INFO)
    end)
end

return {
    name = "join_counter",
    depends = { "oakmc_runtime", "oakmc_storage" },
    init = init,
}
```

`OAKMC_RUNTIME` registers only one native OakMC callback for each event type.
Handlers are ordered by descending priority and then registration order;
setting `event.cancelled = true` stops later handlers. Timer names are global
to the service, so prefix them with the consumer plugin name.

`OAKMC_STORAGE` provides `get(namespace, key [, default])`, `list(namespace)`,
`set(namespace, key, value)`, `update(namespace, key, callback)`,
`delete(namespace, key)`, and `reload()`. Operations return `ok` first; reads
and returned values are deep copies. `update` holds the storage lock across the
latest read, callback, and atomic write, and returning `nil` deletes the key.
Set `OAKMC_STORAGE_DATA_FILE` to override the default `plugins/storage.data`.

`example_hub_command.lua` requires a `proxy_transfer` plugin entry in the game
server's own `plugins/` directory. Its defaults target Velocity's fixed
`lobby = 127.0.0.1:10000` backend and can be overridden with
`OAKMC_HUB_SERVER_NAME`, `OAKMC_HUB_HOST`, and `OAKMC_HUB_PORT`. Unlike
`example_transfer.lua`, it does not send Minecraft's native Transfer packet;
the Velocity bridge consumes `oakmc:proxy_transfer` and switches the existing
proxy connection internally.
