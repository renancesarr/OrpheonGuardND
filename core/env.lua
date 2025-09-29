-- core/env.lua
-- Simple dotenv-like loader for Lua (works with Lua 5.2+)
-- Usage:
--   local env = require("core.env")
--   env.load(".env")           -- opcional; se não chamar, ainda lê do os.getenv
--   local v = env.getenv("PROXY")

local M = {
    data = {}
}

local function trim(s)
    if not s then return nil end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Parse a single line like: KEY=VALUE
-- Supports quotes: KEY="value with spaces" or KEY='single quoted'
local function parse_line(line)
    -- remove leading/trailing whitespace
    line = trim(line)
    if line == "" then return nil end
    -- ignore comments
    if line:match("^#") then return nil end
    -- key = value
    local k, v = line:match("^([^=]+)=(.*)$")
    if not k then return nil end
    k = trim(k)
    v = trim(v)
    -- strip surrounding quotes
    if v:match('^".*"$') or v:match("^'.*'$") then
        v = v:sub(2, -2)
    end
    return k, v
end

-- Load .env file into M.data (doesn't overwrite existing os.getenv unless asked)
function M.load(path, opts)
    opts = opts or {}
    path = path or ".env"
    local f, err = io.open(path, "r")
    if not f then return nil, "open_failed: " .. tostring(err) end
    for line in f:lines() do
        -- remove inline comments after value if present (#)
        -- but be conservative: only remove if there's a space then #
        local cleaned = line:gsub("%s+#.*$", "")
        local k, v = parse_line(cleaned)
        if k and v then
            M.data[k] = v
            if opts.export and type(opts.export) == "function" then
                -- allow caller to provide a setter (e.g., posix.setenv) to export to process env
                pcall(opts.export, k, v)
            end
        end
    end
    f:close()
    return true
end

-- getenv: first check real env (os.getenv), then loaded .env data
function M.getenv(k)
    local v = os.getenv(k)
    if v and v ~= "" then return v end
    return M.data[k]
end

-- helper: ensure key exists either in os.getenv or loaded data
function M.require(k)
    local v = M.getenv(k)
    if not v or v == "" then
        return nil, "env_required: " .. tostring(k)
    end
    return v
end

return M
