local M = {}

-- ==== Helpers ====

local function atomic_write(path, content)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return nil, "open_tmp_failed: " .. tostring(err) end
    f:write(content)
    f:close()
    local ok, renerr = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        return nil, "rename_failed: " .. tostring(renerr)
    end
    return true
end

local function fetch_with_curl(url)
    local cmd = string.format("curl -sS -f -L %q", url)
    local p = io.popen(cmd)
    if not p then return nil, "popen_failed" end
    local body = p:read("*a")
    local ok, exit_type, code = p:close()
    if not ok then
        return nil, string.format("curl_failed: %s/%s", tostring(exit_type), tostring(code))
    end
    return body
end

local function normalize_proxy_text(body)
    if not body then return {} end
    -- normaliza todos os tipos de break
    body = body:gsub("</br>", "\n")
    body = body:gsub("<br%s*/?>", "\n")
    body = body:gsub("<BR%s*/?>", "\n")

    -- remove tags HTML simples (<pre>, </pre>, etc)
    body = body:gsub("<[^>]+>", "")

    -- uniformiza separadores
    body = body:gsub(",", "\n")
    body = body:gsub(";", "\n")
    body = body:gsub("\r\n", "\n")
    body = body:gsub("\r", "\n")

    local t, seen = {}, {}
    for line in body:gmatch("[^\n]+") do
        local s = line:gsub("^%s*(.-)%s*$", "%1") -- trim
        if s ~= "" then
            local host, port = s:match("^%[([^%]]+)%]:(%d+)$")
            if not host then host, port = s:match("^([^:]+):(%d+)$") end
            if host and port then
                local key = string.format("%s:%s", host, port)
                if not seen[key] then
                    table.insert(t, key)
                    seen[key] = true
                end
            end
        end
    end
    return t
end


-- ==== API pública ====

-- Busca proxies via URL → retorna { "ip:port", ... }
function M.fetch(url)
    if not url or url == "" then
        return nil, "url_not_provided"
    end

    local body, ferr = fetch_with_curl(url)
    if not body then
        return nil, "fetch_failed: " .. tostring(ferr)
    end

    local proxies = normalize_proxy_text(body)
    if #proxies == 0 then
        return nil, "no_proxies_found"
    end

    return proxies
end

-- Escreve proxies em arquivo
function M.write(filename, proxies)
    if not proxies or #proxies == 0 then
        return nil, "empty_proxy_list"
    end

    local content = table.concat(proxies, "\n") .. "\n"
    local ok, werr = atomic_write(filename, content)
    if not ok then
        return nil, "write_failed: " .. tostring(werr)
    end
    return true, #proxies
end

return M