param(
    [string]$Target = "scripts/awacs"
)

$ErrorActionPreference = "Stop"

$luaExe = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe"
$luacheckScript = Join-Path $env:APPDATA "luarocks\bin\luacheck"
$luaShare = Join-Path $env:APPDATA "luarocks\share\lua\5.4"
$luaLib = Join-Path $env:APPDATA "luarocks\lib\lua\5.4"

if (-not (Test-Path $luaExe)) {
    throw "lua.exe not found at $luaExe"
}

if (-not (Test-Path $luacheckScript)) {
    throw "luacheck script not found at $luacheckScript. Run: luarocks install luacheck"
}

$env:LUA_PATH = "$luaShare\\?.lua;$luaShare\\?\\init.lua;;"
$env:LUA_CPATH = "$luaLib\\?.dll;;"

& $luaExe $luacheckScript --config .luacheckrc $Target
exit $LASTEXITCODE
