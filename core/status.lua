local M = {}

local function run(cmd)
    local f = io.popen(cmd .. " 2>&1")
    if not f then return nil, "falha_execucao" end
    local out = f:read("*a")
    local ok, _, code = f:close()
    return ok, out, code
end

-- Redsocks rodando na porta?
function M.check_redsocks(port)
    port = port or 8123
    local ok, out = run("ss -ltnp | grep :" .. tostring(port))
    if ok and out and out:match("redsocks") then
        return true, out
    end
    return false, out or ""
end

-- Proxy atual do redsocks.conf
function M.current_proxy(path)
    path = path or "/etc/redsocks.conf"
    local f = io.open(path, "r")
    if not f then return nil, "arquivo_inexistente" end
    local content = f:read("*a")
    f:close()

    local ip, port = content:match("ip%s*=%s*(%d+%.%d+%.%d+%.%d+);%s*%s*port%s*=%s*(%d+);")
    if ip and port then
        return ip .. ":" .. port
    end
    return nil, "nao_detectado"
end

-- Regras iptables
function M.iptables_summary()
    local ok1, out1 = run("iptables -t nat -L REDSOCKS -n -v")
    local ok2, out2 = run("iptables -t nat -L OUTPUT -n -v --line-numbers")
    return { redsocks_chain = out1 or "", output_chain = out2 or "" }
end

return M
