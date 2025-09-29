#!/usr/bin/env lua
-- tools/iptables_backup.lua
-- Backup do iptables (IPv4 e IPv6) em tools/iptables_backups/
-- Uso: sudo lua tools/iptables_backup.lua
-- Requer privilégios root para iptables-save funcionar corretamente.

local lfs_ok, lfs = pcall(require, "lfs")

local function now_ts()
    return os.date("%Y%m%d-%H%M%S")
end

local function run_capture(cmd)
    local fh = io.popen(cmd .. " 2>&1")
    if not fh then return nil, "popen_failed" end
    local out = fh:read("*a")
    local ok, _, code = fh:close()
    return ok, out or "", code
end

local function ensure_dir(path)
    -- tenta criar recursivamente
    local ok, err = lfs_ok and lfs.mkdir(path)
    if not ok and not lfs_ok then
        -- fallback: tentar criar com mkdir via comando (única exceção)
        local ok2 = os.execute("mkdir -p " .. string.format("%q", path))
        if not ok2 then return nil, "mkdir_failed" end
        return true
    end
    -- if lfs.mkdir returned nil possibly because exists; ensure exists
    if not lfs_ok and not ok then
        -- nothing else
    end
    return true
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function backup_dir()
    local base = debug.getinfo(1, "S").source:match("@?(.*)/[^/]+$") or "."
    return base .. "/iptables_backups"
end

-- main
local dir = backup_dir()
local ok = ensure_dir(dir)
if not ok then
    io.stderr:write("Erro criando diretório de backup: " .. tostring(ok) .. "\n")
    os.exit(1)
end

local ts = now_ts()
local out4 = string.format("%s/iptables-v4-%s.rules", dir, ts)
local out6 = string.format("%s/iptables-v6-%s.rules", dir, ts)

io.write("Fazendo backup IPv4 -> " .. out4 .. "\n")
local ok4, body4 = run_capture("iptables-save")
if ok4 then
    local wok, werr = write_file(out4, body4)
    if wok then
        io.write("Backup IPv4 salvo.\n")
    else
        io.stderr:write("Erro salvando IPv4: " .. tostring(werr) .. "\n")
    end
else
    io.stderr:write("iptables-save falhou: " .. tostring(body4) .. "\n")
end

io.write("Fazendo backup IPv6 -> " .. out6 .. "\n")
local ok6, body6 = run_capture("ip6tables-save")
if ok6 then
    local wok6, werr6 = write_file(out6, body6)
    if wok6 then
        io.write("Backup IPv6 salvo (se o sistema suportar IPv6).\n")
    else
        io.stderr:write("Erro salvando IPv6: " .. tostring(werr6) .. "\n")
    end
else
    -- se ip6tables-save não existe ou falhou, apenas avisa e remove arquivo vazio
    io.write("Aviso: ip6tables-save falhou ou não disponível: " .. tostring(body6) .. "\n")
end

io.write("\nBackups gerados em: " .. dir .. "\n")
-- listar arquivos (usa lfs se disponível)
if lfs_ok then
    for file in lfs.dir(dir) do
        if file ~= "." and file ~= ".." then
            local attr = lfs.attributes(dir .. "/" .. file)
            if attr and attr.mode == "file" then
                io.write(" - " .. file .. "\n")
            end
        end
    end
else
    local okls, outls = run_capture('ls -1 ' .. string.format("%q", dir) .. ' 2>/dev/null || true')
    if outls and outls ~= "" then
        for line in outls:gmatch("[^\n]+") do io.write(" - " .. line .. "\n") end
    end
end

io.write("\nPronto.\n")
