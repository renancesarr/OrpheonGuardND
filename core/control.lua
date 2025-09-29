-- core/control.lua
-- Controle do processo redsocks: start/stop/restart com verificação de porta

local M = {}

-- executa um comando de shell e retorna ok,saida
local function run(cmd)
    local f = io.popen(cmd .. " 2>&1")
    if not f then return nil, "falha_execucao" end
    local out = f:read("*a")
    local ok, _, code = f:close()
    return ok, out, code
end

-- verifica se porta está em uso por redsocks
local function port_in_use(port)
    local ok, out = run("ss -ltnp | grep :" .. tostring(port))
    if ok and out and out:match("redsocks") then
        return true
    end
    return false
end

function M.stop(local_port)
    local_port = local_port or 8123
    run("pkill -9 redsocks")

    -- espera até a porta liberar (até 2s)
    local deadline = os.time() + 2
    while os.time() < deadline do
        if not port_in_use(local_port) then
            return true, "parado"
        end
        os.execute("sleep 0.2")
    end
    return nil, "nao_consegui_matar_redsocks"
end

function M.start(config_path, local_port)
    config_path = config_path or "/etc/redsocks.conf"
    local_port = local_port or 8123

    -- tenta iniciar redsocks em background
    local ok, out, code = run("redsocks -c " .. config_path .. " &")
    if not ok then
        return nil, "falha_execucao: " .. tostring(out)
    end

    -- esperar até 2s a porta abrir
    local deadline = os.time() + 2
    while os.time() < deadline do
        if port_in_use(local_port) then
            return true, "rodando"
        end
        os.execute("sleep 0.2")
    end

    return nil, "redsocks_nao_iniciou_na_porta_" .. tostring(local_port)
end

function M.restart(config_path, local_port)
    M.stop(local_port)
    os.execute("sleep 0.5")
    return M.start(config_path, local_port)
end

return M
