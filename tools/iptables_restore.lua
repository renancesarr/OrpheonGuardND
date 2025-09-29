#!/usr/bin/env lua
-- tools/iptables_restore.lua
-- Lista backups em tools/iptables_backups e pergunta qual restaurar
-- Uso: sudo lua tools/iptables_restore.lua

local lfs_ok, lfs = pcall(require, "lfs")

local function run_capture(cmd)
    local fh = io.popen(cmd .. " 2>&1")
    if not fh then return nil, "popen_failed" end
    local out = fh:read("*a")
    local ok, _, code = fh:close()
    return ok, out or "", code
end

local function get_script_dir()
    local info = debug.getinfo(1, "S").source
    local script_path = info:match("@?(.*)")
    if not script_path then return "." end
    local dir = script_path:match("^(.*)/") or "."
    -- normalize absolute
    local ok, out = run_capture("cd " .. string.format("%q", dir) .. " && pwd")
    if ok and out then return out:gsub("%s+$", "") end
    return dir
end

local function list_files(dir)
    local items = {}
    if lfs_ok then
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." then
                local attr = lfs.attributes(dir .. "/" .. file)
                if attr and attr.mode == "file" then table.insert(items, file) end
            end
        end
    else
        local ok, out = run_capture('ls -1 ' .. string.format("%q", dir) .. ' 2>/dev/null || true')
        if out then
            for line in out:gmatch("[^\n]+") do
                if line ~= "" then table.insert(items, line) end
            end
        end
    end
    table.sort(items)
    return items
end

local function prompt(msg)
    io.write(msg); io.flush(); return io.read()
end

-- main
local base = get_script_dir()
local backup_dir = base .. "/iptables_backups"

-- check dir exists
local ok, out = run_capture('test -d ' .. string.format("%q", backup_dir) .. ' && echo yes || echo no')
if not ok then
    io.stderr:write("Erro verificando diretório de backups.\n"); os.exit(1)
end
if not out:match("yes") then
    io.stderr:write("Diretório de backups não encontrado: " .. backup_dir .. "\n"); os.exit(1)
end

local files = list_files(backup_dir)
if #files == 0 then
    io.stderr:write("Nenhum arquivo de backup encontrado em: " .. backup_dir .. "\n"); os.exit(1)
end

io.write("Backups disponíveis:\n")
for i, name in ipairs(files) do
    io.write(string.format("%3d) %s\n", i, name))
end

local sel = prompt("Escolha o número do backup a restaurar (ou 'q' para sair): ")
if not sel or sel == "" then io.write("Abortando.\n"); os.exit(0) end
if sel:lower() == "q" then io.write("Abortando.\n"); os.exit(0) end
local idx = tonumber(sel)
if not idx or idx < 1 or idx > #files then io.stderr:write("Seleção inválida.\n"); os.exit(1) end

local chosen = files[idx]
local chosen_path = backup_dir .. "/" .. chosen

-- confirm
local conf = prompt("Confirmar restauração de '" .. chosen .. "'? (y/N): ")
if not conf or (conf:lower() ~= "y" and conf:lower() ~= "yes") then io.write("Restauração cancelada.\n"); os.exit(0) end

-- decide v4/v6 by filename
local is_v6 = false
if chosen:match("v6") then is_v6 = true end

io.write("Restaurando " .. (is_v6 and "IPv6" or "IPv4") .. " a partir de: " .. chosen_path .. "\n")

-- perform restore
local cmd
if is_v6 then
    cmd = "ip6tables-restore < " .. string.format("%q", chosen_path)
else
    cmd = "iptables-restore < " .. string.format("%q", chosen_path)
end
local ok2, out2 = run_capture(cmd)
if not ok2 then
    io.stderr:write("Falha ao restaurar: " .. tostring(out2) .. "\n"); os.exit(1)
end

io.write("Restauração concluída com sucesso.\n")
