local M = {}

-- Lê arquivo de proxies (cada linha "host:port") e retorna lista de {host, port}
function M.load(filename)
    local proxies = {}
    local f, err = io.open(filename, "r")
    if not f then
        return nil, "cannot_open_file: " .. tostring(err)
    end

    for line in f:lines() do
        line = line:gsub("^%s*(.-)%s*$", "%1") -- trim
        if line ~= "" then
            local host, port = line:match("^%[([^%]]+)%]:(%d+)$")
            if not host then host, port = line:match("^([^:]+):(%d+)$") end
            if host and port then
                table.insert(proxies, { host = host, port = tonumber(port) })
            end
        end
    end
    f:close()

    return proxies
end

return M