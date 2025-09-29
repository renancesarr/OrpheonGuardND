local M = {}

-- Gera um redsocks.conf com apenas um proxy
-- proxy: { host = "ip", port = number, latency = number }
-- opts:
--   path: caminho do arquivo de saída (default: /etc/redsocks.conf)
--   local_ip: IP local para escuta (default: 127.0.0.1)
--   local_port: porta local (default: 8123)
function M.generate(proxy, opts)
    if not proxy then
        return nil, "proxy_invalido"
    end

    opts = opts or {}
    local path = opts.path or "/etc/redsocks.conf"
    local local_ip = opts.local_ip or "127.0.0.1"
    local local_port = opts.local_port or 8123  -- padrão ajustado

    -- se já existir, apagar antes de recriar
    local fcheck = io.open(path, "r")
    if fcheck then
        fcheck:close()
        os.remove(path)
    end

    -- base config + bloco único
    local config = string.format([[
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = %s;
    local_port = %d;
    type = socks5;
    ip = %s;
    port = %d;
    login = "";
    password = "";
}
]], local_ip, local_port, proxy.host, proxy.port)

    local f, err = io.open(path, "w")
    if not f then
        return nil, "erro_abrir_arquivo: " .. tostring(err)
    end
    f:write(config)
    f:close()

    return true, path
end

return M
