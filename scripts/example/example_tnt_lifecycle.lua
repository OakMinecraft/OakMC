OAKMC_GAME_KEY = rawget(_G, "OAKMC_GAME_KEY") or "tnt"
OAKMC_GAME_NAME = rawget(_G, "OAKMC_GAME_NAME") or "TNT 狂欢"
OAKMC_GAME_CLOSED_COMMAND = rawget(_G, "OAKMC_GAME_CLOSED_COMMAND") or "tnt-server-closed"

return dofile("scripts/example/example_game_lifecycle.lua")
