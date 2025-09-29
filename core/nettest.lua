-- core/nettest.lua
-- OrpheonGuardND - testar proxies (conexão TCP) e medir latência
-- Requer luasocket
-- STDIOX & Orpheon

local socket = require("socket")
local M = {}

-- helper: conta elementos de uma tabela (funciona para dict/map)
local function table_size(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Testa uma lista de proxies (string "host:port" ou table {host,port})
-- opts:
--   timeout: tempo máx. por conexão (default 3s)
--   concurrency: nº máx. de sockets simultâneos (default 60)
-- Retorna lista ordenada { host, port, latency }
function M.test_all(proxy_list, opts)
    opts = opts or {}
    local timeout = opts.timeout or 3
    local concurrency = opts.concurrency or 60

    -- normaliza proxies
    local normalized = {}
    for _, p in ipairs(proxy_list) do
        if type(p) == "string" then
            local host, port = p:match("^%[([^%]]+)%]:(%d+)$")
            if not host then host, port = p:match("^([^:]+):(%d+)$") end
            if host and port then
                table.insert(normalized, { host = host, port = tonumber(port) })
            end
        elseif type(p) == "table" and p.host and p.port then
            table.insert(normalized, { host = tostring(p.host), port = tonumber(p.port) })
        end
    end

    local results = {}      -- proxies conectados com sucesso
    local pending = {}      -- socket -> entry
    local idx = 1
    local total = #normalized
    local now = socket.gettime

    -- função para iniciar uma conexão não-bloqueante
    local function start_connect(entry)
        local s = socket.tcp()
        if not s then return nil, "socket_create_failed" end
        s:settimeout(0) -- non-blocking
        local ok, err = s:connect(entry.host, entry.port)
        if ok then
            local latency = now() - entry.start
            s:close()
            return "immediate", latency
        else
            return s, err -- normal em non-blocking
        end
    end

    -- inicia lote inicial
    while idx <= total and table_size(pending) < concurrency do
        local entry = normalized[idx]
        entry.start = now()
        entry.deadline = entry.start + timeout
        local sock, err = start_connect(entry)
        if sock == "immediate" then
            table.insert(results, { host = entry.host, port = entry.port, latency = err })
        elseif type(sock) == "userdata" or type(sock) == "table" then
            pending[sock] = entry
        end
        idx = idx + 1
    end

    -- helper: cria lista de sockets pra select
    local function build_write_list()
        local t = {}
        for s,_ in pairs(pending) do
            table.insert(t, s)
        end
        return t
    end

    -- loop principal
    while (next(pending) ~= nil) or idx <= total do
        -- completa janela de concorrência
        while idx <= total and table_size(pending) < concurrency do
            local entry = normalized[idx]
            entry.start = now()
            entry.deadline = entry.start + timeout
            local sock, err = start_connect(entry)
            if sock == "immediate" then
                table.insert(results, { host = entry.host, port = entry.port, latency = err })
            elseif type(sock) == "userdata" or type(sock) == "table" then
                pending[sock] = entry
            end
            idx = idx + 1
        end

        local write_list = build_write_list()
        if #write_list == 0 then
            socket.sleep(0.01)
        else
            local recvt, sendt, err = socket.select(nil, write_list, 0.1)
            for _, s in ipairs(sendt) do
                local meta = pending[s]
                if not meta then
                    pcall(s.close, s)
                else
                    local connected = false
                    local ok, peer = pcall(s.getpeername, s)
                    if ok and peer then
                        connected = true
                    else
                        local ok2, err2 = s:connect(meta.host, meta.port)
                        if ok2 then connected = true end
                        if err2 and (err2:find("already") or err2:find("isconnected")) then
                            connected = true
                        end
                    end

                    if connected then
                        local latency = now() - meta.start
                        table.insert(results, { host = meta.host, port = meta.port, latency = latency })
                        pending[s] = nil
                        pcall(s.close, s)
                    elseif now() >= meta.deadline then
                        pending[s] = nil
                        pcall(s.close, s)
                    end
                end
            end

            -- limpa timeouts que escaparam do select
            local to_remove = {}
            for s, meta in pairs(pending) do
                if now() >= meta.deadline then
                    table.insert(to_remove, s)
                end
            end
            for _, s in ipairs(to_remove) do
                pending[s] = nil
                pcall(s.close, s)
            end
        end
    end

    -- ordena por latência
    table.sort(results, function(a,b) return a.latency < b.latency end)
    return results
end

return M
