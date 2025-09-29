-- core/iptables.lua
-- Backup, restauração e reset do iptables
-- STDIOX & Orpheon

local M = {}
local lfs_ok, lfs = pcall(require, "lfs")

local function run_capture(cmd)
    local fh = io.popen(cmd .. " 2>&1")
    if not fh then return nil, "popen_failed" end
    local out = fh:read("*a")
    local ok, _, code = fh:close()
    return ok, out or "", code
end

-- corrigido: trata "File exists" como sucesso
local function ensure_dir(path)
    if lfs_ok then
        local attr = lfs.attributes(path)
        if not attr then
            local ok, err = lfs.mkdir(path)
            if not ok then
                if err and err:match("exist") then
                    return true
                end
                return nil, err
            end
        end
        return true
    else
        local ok = os.execute("mkdir -p " .. string.format("%q", path))
        if ok == true or ok == 0 then
            return true
        else
            return nil, "mkdir_failed"
        end
    end
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function backup_dir()
    return "./tools/iptables_backups"
end

-- Cria backup do iptables com timestamp
function M.backup()
    local dir = backup_dir()
    local ok, err = ensure_dir(dir)
    if not ok then return nil, "mkdir_failed: " .. tostring(err) end

    local ts = os.date("%Y%m%d-%H%M%S")
    local out4 = string.format("%s/iptables-v4-%s.rules", dir, ts)
    local out6 = string.format("%s/iptables-v6-%s.rules", dir, ts)

    local ok4, body4 = run_capture("iptables-save")
    if ok4 and body4 and body4 ~= "" then
        write_file(out4, body4)
    end

    local ok6, body6 = run_capture("ip6tables-save")
    if ok6 and body6 and body6 ~= "" then
        write_file(out6, body6)
    end

    return true, { out4 = out4, out6 = out6 }
end

-- Lista backups disponíveis
local function list_backups()
    local dir = backup_dir()
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
    return items, dir
end

-- Restaurar iptables de um backup
function M.restore_interactive()
    local files, dir = list_backups()
    if #files == 0 then
        return nil, "nenhum_backup_encontrado"
    end

    print("Backups disponíveis em " .. dir .. ":")
    for i, f in ipairs(files) do
        print(string.format("%3d) %s", i, f))
    end

    io.write("Escolha o número do backup a restaurar (ou 'q' para sair): ")
    local sel = io.read()
    if not sel or sel:lower() == "q" then return nil, "abortado" end

    local idx = tonumber(sel)
    if not idx or idx < 1 or idx > #files then
        return nil, "seleção_inválida"
    end

    local chosen = files[idx]
    local chosen_path = dir .. "/" .. chosen
    io.write("Confirmar restauração de " .. chosen .. "? (y/N): ")
    local conf = io.read()
    if not conf or (conf:lower() ~= "y" and conf:lower() ~= "yes") then
        return nil, "cancelado"
    end

    local cmd
    if chosen:match("v6") then
        cmd = "ip6tables-restore < " .. string.format("%q", chosen_path)
    else
        cmd = "iptables-restore < " .. string.format("%q", chosen_path)
    end
    local ok, out = run_capture(cmd)
    if not ok then return nil, "falha_restore: " .. tostring(out) end

    return true, "restaurado: " .. chosen
end

-- Resetar iptables para estado inicial (sem regras, tudo ACCEPT)
function M.reset()
    local cmds = {
        "iptables -F",
        "iptables -t nat -F",
        "iptables -t mangle -F",
        "iptables -t raw -F",
        "iptables -X",
        "iptables -t nat -X",
        "iptables -t mangle -X",
        "iptables -t raw -X",
        "iptables -P INPUT ACCEPT",
        "iptables -P FORWARD ACCEPT",
        "iptables -P OUTPUT ACCEPT",
    }
    for _, c in ipairs(cmds) do
        run_capture(c)
    end

    local cmds6 = {
        "ip6tables -F",
        "ip6tables -t nat -F",
        "ip6tables -t mangle -F",
        "ip6tables -t raw -F",
        "ip6tables -X",
        "ip6tables -t nat -X",
        "ip6tables -t mangle -X",
        "ip6tables -t raw -X",
        "ip6tables -P INPUT ACCEPT",
        "ip6tables -P FORWARD ACCEPT",
        "ip6tables -P OUTPUT ACCEPT",
    }
    for _, c in ipairs(cmds6) do
        run_capture(c)
    end

    return true, "iptables resetado para estado inicial"
end

return M
