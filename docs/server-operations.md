# OakMC Server Operations

[中文](server-operations-zh.md)

This guide covers the maintained runtime's working-directory model, startup
options, configuration reloads, signed remote commands, the Admin HTTP API, and
isolated child instances. Build details remain in the
[root README](../README.md), and Lua API signatures are in
[`lua-api-reference.md`](lua-api-reference.md).

## 1. Working Directory

OakMC resolves runtime files relative to the directory from which `mcserver` is
started, not relative to the executable. A normal source-tree build therefore
starts the server from the repository root:

```bash
./build-debug/src/mcserver
```

The first start creates the active world, `server.properties`, `plugins/`, and
logging directories in that current directory. Run the binary from a dedicated
directory when you want a separate server installation.

Common runtime paths are:

- `server.properties`: main server configuration
- `admin.properties`: optional OakMC Manager / Admin HTTP API configuration
- `server-icon.png`: optional status favicon supplied by the operator
- `remote.properties`: optional signed-command bridge configuration
- `plugins/*.lua`: Lua plugins loaded in dependency order
- `log/`: timestamped server logs
- `<level-name>/level.dat`: vanilla Java world metadata and seed
- `<level-name>/region/*.mca`: vanilla Java Anvil region files
- `whitelist.json`, `banned-players.json`, `banned-ips.json`: moderation data
- `instances/<name>/`: working directories created for child server instances
- `crashes/`: Breakpad output when Breakpad is enabled and initializes

`admin.properties` is created with the Admin API disabled by default.
`remote.properties` and `server-icon.png` are not generated automatically.

## 2. Startup Options

Show the executable's accepted options:

```bash
./build-debug/src/mcserver --help
```

Available options are:

```text
-p, --port, --server-port PORT
-m, --max-players, --players PLAYERS
--remote-address ADDRESS
--remote-port PORT
--remote-id ID
--remote-secret-file PATH
--remote-allowed-commands COMMANDS
-h, --help
```

Long options accept either a separate value or `--option=value`:

```bash
./build-debug/src/mcserver --port 25566 --max-players=50
```

Remote options can override `remote.properties`, or configure the bridge when
that file is absent:

```bash
./build-debug/src/mcserver \
  --remote-port 25576 \
  --remote-id survival \
  --remote-secret-file /run/secrets/oakmc-remote \
  --remote-allowed-commands stop,say
```

The port must be in `1..65535`; the player limit must be at least `1`.
Invalid or unknown options print usage and exit with status `2` before runtime
initialization.

Configuration files are read first, then environment and command-line
overrides are applied. These values affect only the current process and never
rewrite either properties file. Server overrides are reapplied after `reload`;
Remote overrides are reapplied after `remote reload`. Listening sockets are not
rebound during a reload, so port or address changes require a restart.

Each accepted Minecraft connection must send a complete initial Handshake
within approximately five seconds. Status and login reads also use bounded
receive waits. Malformed packet frames, truncated fields, unexpected packet
ids, and payloads that do not satisfy the state-specific schema are rejected
and the connection is closed. These limits are currently compile-time runtime
behavior rather than `server.properties` settings.

## 3. `server.properties`

The maintained configuration keys are:

| Key | Purpose |
| --- | --- |
| `server-address` | IPv4 address on which the Minecraft server listens |
| `server-port` | Minecraft server port; default runtime port is `25565` |
| `max-players` | Status response and login capacity |
| `online-mode` | Enables Mojang session verification |
| `white-list` | Requires players to be present in `whitelist.json` |
| `allow-flight` | Flight-related server policy |
| `difficulty` | Default difficulty name |
| `gamemode` | `survival`, `creative`, `adventure`, `spectator`, or `0..3` |
| `motd` | Status-list description |
| `level-name` | Single active save directory; defaults to `world` |
| `level-seed` | Seed used when a new `level.dat` is created |
| `view-distance` | Chunk streaming radius |
| `world-chunk-cache-size` | Shared chunk-cache capacity; values below `1024` are ignored |
| `session_server_url` | Online-mode session verification endpoint |

Existing worlds keep the seed recorded in `level.dat`; changing `level-seed`
does not rewrite an existing world's seed. OakMC currently uses only the
overworld region directory. Missing chunks are initialized as empty chunks,
because terrain generation is not part of the maintained runtime.

Keep the default `session_server_url` unless a compatible authentication
service is intentionally deployed.

## 4. Reload And World Switching

The relevant console commands are:

```text
reload
reload-lua
world current
world load <name>
remote reload
```

- `reload` reloads `server.properties` and Lua plugins without disconnecting
  online players. Command-line port/player overrides are reapplied. A changed
  `level-name` triggers the same connection-preserving switch as `world load`.
- `reload-lua` unloads plugins in reverse dependency order and loads them again
  without re-reading `server.properties`.
- `world load <name>` flushes and quiesces the old chunk cache, reloads Lua to
  clear world-owned plugin state, sends Respawn, teleports players to the new
  spawn, and rebuilds chunk queues. Names may contain only letters, digits,
  `_`, and `-`.
- `remote reload` re-reads the local server identity, shared secret, and command
  allow-list, then reapplies `OAKMC_REMOTE_SECRET` and the Remote startup
  options. Restart after changing `listen-address` or `listen-port` so the
  listener can be rebound.

## 5. Signed Remote Command Bridge

The bridge is disabled when `remote.properties` is missing or `enabled=false`.
To configure it:

```bash
cp remote.properties.example remote.properties
openssl rand -hex 32
```

Put the generated value in `secret`, select a unique `server-id` for each
server, and use the same secret only on servers that belong to the same trusted
cluster.

```properties
enabled=true
listen-address=127.0.0.1
listen-port=25575
server-id=hub
secret=replace-with-a-generated-secret
allowed-commands=say,list,weather
```

Configuration behavior:

- `listen-address` and `listen-port` describe this server's incoming listener.
- `server-id` identifies this receiver and is checked against every request's
  target id.
- `secret` must contain at least 32 characters. It is never exposed to Lua.
- `allowed-commands` is a comma-separated allow-list based on the first command
  token. An empty list rejects every incoming command.
- outgoing peers are not stored in this file. The target id, IPv4 address, and
  port are supplied to `remote send` or `mcs_remote_command_send()`.

Startup overrides use this precedence, from highest to lowest:

```text
Remote command-line option
OAKMC_REMOTE_SECRET (secret only)
remote.properties
built-in defaults
```

Any Remote command-line option requests that the bridge be enabled. The final
merged configuration must contain a valid `server-id` and a secret of at least
32 characters. Without `remote.properties`, the default listener is
`127.0.0.1:25575`; an omitted or explicitly empty allow-list rejects every
incoming command.

Use `--remote-secret-file PATH` for process launchers and containers. The file
is re-read by `remote reload`, leading and trailing whitespace is ignored, and
its contents are never logged. OakMC intentionally has no plaintext
`--remote-secret` option because command arguments can be exposed through
process listings and shell history. `OAKMC_REMOTE_SECRET` is available when a
secret environment variable is more convenient, but a secret file generally
has a smaller accidental-exposure surface.

Example:

```text
remote send survival 127.0.0.1 25576 say Maintenance in 5 minutes
```

Requests use HMAC-SHA256 and include the source id, target id, timestamp, random
nonce, and full command. The receiver enforces a 30-second clock window and a
nonce replay cache before executing the command in console/OP context. The
receiver's allow-list still applies.

Keep the listener on loopback whenever possible. For cross-host deployments,
place it behind a firewall or private VPN, synchronize system clocks, use a
narrow allow-list, and never expose the cluster secret in plugin source or
logs.

## 6. Admin HTTP API

OakMC includes an optional HTTP control API intended for OakMC Manager and
operator tooling. It is configured separately from `server.properties` in
`admin.properties`. The file is created automatically on startup with the API
disabled:

```properties
# OakMC Manager / Admin HTTP API
# Keep disabled unless you need GUI or remote management.
enabled=false
listen-address=127.0.0.1
listen-port=25580
# Required when enabled. Use at least 32 random characters.
token=
allow-origin=http://127.0.0.1:1420
```

To enable it, set `enabled=true`, generate a token with at least 32 random
characters, and restart the server:

```bash
openssl rand -hex 32
```

Configuration behavior:

- `listen-address` and `listen-port` bind the HTTP listener. Only IPv4 listen
  addresses are currently accepted.
- `token` is required when enabled and is checked on every endpoint.
- `allow-origin` controls the CORS `Access-Control-Allow-Origin` value used by
  browser-based tooling. Leave it narrow when using a GUI.
- Admin API configuration is read at process startup. Address, port, token, and
  CORS changes require a restart.

Requests normally authenticate with a bearer token:

```bash
curl -H "Authorization: Bearer $OAKMC_ADMIN_TOKEN" \
  http://127.0.0.1:25580/api/v1/status
```

The implementation also accepts `?token=...` for clients such as browser
`EventSource` that cannot set an `Authorization` header. Prefer the header form
for ordinary HTTP clients so tokens are less likely to appear in logs or copied
URLs.

Supported endpoints:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/status` | Return server version, protocol, listen address, player counts, and view distance |
| `GET` | `/api/v1/players` | List online players with name, UUID, entity id, protocol, and initialization state |
| `POST` | `/api/v1/command` | Execute a console/OP command from JSON body `{"command":"say hello"}` |
| `POST` | `/api/v1/players/<name>/kick` | Kick an online player |
| `POST` | `/api/v1/players/<name>/ban` | Ban a player; body may include `{"kick":true}` |
| `GET` | `/api/v1/plugins` | List `plugins/*.lua` and `plugins/*.lua.disabled` files |
| `PATCH` | `/api/v1/plugins/<file>` | Enable or disable a plugin with body `{"enabled":true}` |
| `POST` | `/api/v1/plugins/<file>/enable` | Rename `<file>.disabled` back to `<file>` |
| `POST` | `/api/v1/plugins/<file>/disable` | Rename `<file>` to `<file>.disabled` |
| `POST` | `/api/v1/plugins/reload` | Execute `reload-lua` |
| `GET` | `/api/v1/events` | Server-Sent Events stream for log lines and inferred player join/leave events |

Successful JSON responses include `{"ok":true,...}` or `{"ok":true}`.
Errors use `{"ok":false,"error":"..."}` with the relevant HTTP status. The
SSE stream emits `log_line`, `player_join`, and `player_left` events; join and
leave events are inferred from log lines, so treat them as a convenience signal
rather than the authoritative player state.

This API can run console commands, change plugin files, and expose live server
state. Keep it on loopback when possible. If it must be reachable from another
host, put it behind TLS termination and network access controls; OakMC's
built-in Admin listener is plain HTTP and relies on the bearer token plus the
surrounding network boundary.

## 7. Isolated Child Instances

Lua plugins can allocate a port and start another OakMC process:

```lua
local port = mcs_server_find_available_port(10000)
assert(port ~= nil)
assert(mcs_server_start_instance("arena_1", port))
```

For a fixed allocation range, use `mcs_server_port_is_available(port)` to
perform a single local bind probe. It returns `true` when the port can currently
be bound and `false` when it is usually occupied or the probe fails. It does
not query a Minecraft server, identify the listener, or monitor child process
health.

Request an independent child Remote listener by supplying a Remote port and an
optional incoming allow-list:

```lua
local game_port = assert(mcs_server_find_available_port(10000))
local remote_port = assert(mcs_server_find_available_port(20000))
assert(mcs_server_start_instance(
    "arena_1", game_port, remote_port, "stop,say"))
```

The allow-list accepts comma-separated command tokens without spaces.

C uses the instance name as the child `server-id` and forwards the parent's
effective secret through a reserved permission-restricted file inside the
instance directory (`0600` on Unix-like systems). Lua never reads or writes
that secret. If the parent has no valid Remote secret, the child still starts
successfully on its Minecraft port, but no Remote arguments are passed and its
Remote bridge stays disabled.

Use the template form when one minigame needs multiple isolated rooms:

```lua
local port = assert(mcs_server_find_available_port(10000))
local remote_port = assert(mcs_server_find_available_port(20000))
assert(mcs_server_start_instance_from(
    "arena-template", "arena-room-1", port, remote_port, "stop"))
```

The template form copies the world, plugins, and server configuration while
omitting `log/`, `crashes/`, `remote.properties`, and the reserved instance
secret file. Each room therefore owns its world data without reusing the
template's Remote listener or credentials. The template function accepts the
same optional `remote_port` and `allowed_commands` arguments. Plugins are
responsible for assigning non-conflicting game and Remote ports and for defining
their own discovery, health-check, and recovery policy.

When Velocity fronts these rooms, keep the unique OakMC process instance name
separate from the proxy registration name. The proxy name is chosen by the
calling plugin and should remain stable when the same logical backend is
re-registered. A port-only name can be sufficient for a single fixed host;
multi-host deployments should include a stable host identifier to avoid name
collisions. OakMC does not prescribe a lobby name or backend naming scheme.

A plugin inside a dynamic room may call
`mcs_server_delete_current_instance()` once the room becomes empty. The call
gracefully shuts down the child and then removes its marked working directory;
it cannot delete the main server, a template, or a regular child instance.

The child runs the same executable with `--port <port>` from
`instances/arena_1/`. When child Remote is active, C also passes
`--remote-port`, `--remote-id`, `--remote-secret-file`, and the optional
allow-list. The child creates and owns its own `server.properties`, world,
plugins, moderation files, and logs. Parent application data such as economy
balances, announcements, player state, and `remote.properties` is not copied.
Use the signed remote bridge for explicit cross-server commands or state
coordination.

Instance names may contain only letters, digits, `_`, and `-`, and the requested
port must differ from the parent server's effective port. Startup succeeds only
after the child accepts a loopback connection. A port can still be claimed
between discovery and process launch, so callers must handle startup failure.
Do not run two live children with the same instance name: the name maps directly
to one working directory, even when different ports are requested.

On Unix-like systems the child is detached and its standard streams are sent to
`/dev/null`; inspect `instances/<name>/log/` when diagnosing it. There is
currently no paired instance-stop API. Use an authenticated remote `stop`
command only if `stop` is deliberately present in that child's incoming
allow-list, or implement another explicit lifecycle policy in the owning
plugin.

## 8. Cross-Process File Locks

When multiple OakMC processes intentionally update one shared local file, Lua
can use the runtime's advisory exclusive lock:

```lua
local lock_id = mcs_server_file_lock("/srv/oakmc/shared/economy.lock", 2000)
if lock_id == nil then
    return false
end

-- Read, update, and replace the protected data file here.

assert(mcs_server_file_unlock(lock_id))
```

The timeout is in milliseconds and must not be negative. Lock ids are local to
the current process, and each process can hold at most 32 locks at once. Always
release a successful lock; the operating system also releases it when the
process exits.

Child instances have different working directories. Use an absolute path, or a
carefully resolved path that names the same lock file in every process, when the
lock is intended to coordinate multiple instances. A lock protects local file
access only; it does not replicate data and is not a replacement for the signed
remote bridge.

## 9. Operational Checklist

Before exposing a server to players:

1. Confirm the client version is Minecraft `26.1.2` / protocol `775`.
2. Review `server-address`, `server-port`, `online-mode`, `white-list`, and
   `max-players`.
3. Back up `level.dat` and `region/*.mca` before testing world-storage changes.
4. Keep `remote.properties` private and bind its listener narrowly.
5. Keep the Admin HTTP API disabled unless needed; when enabled, bind it
   narrowly and use a random token of at least 32 characters.
6. Run `ctest --test-dir build-debug --output-on-failure` after runtime changes.
7. Check `log/` for world DataVersion rejection, authentication errors, plugin
   dependency failures, and remote bridge configuration errors.
