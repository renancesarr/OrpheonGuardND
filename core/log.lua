-- core/log.lua
-- OrpheonGuardND - Logger simples com níveis
-- STDIOX & Orpheon

local M = {}

-- Config
M.levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
M.current_level = M.levels.INFO   -- nível padrão

-- Define nível de log (ex: "DEBUG", "INFO", "WARN", "ERROR")
function M.set_level(level)
    level = tostring(level):upper()
    if M.levels[level] then
        M.current_level = M.levels[level]
    else
        io.stderr:write(string.format("[WARN] Nível de log inválido: %s (usando INFO)\n", level))
        M.current_level = M.levels.INFO
    end
end

-- Formata timestamp
local function timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Função genérica de log
local function log(level, msg, stream)
    if M.levels[level] >= M.current_level then
        local line = string.format("[%s] [%s] %s\n", timestamp(), level, msg)
        stream:write(line)
    end
end

-- Métodos de log
function M.debug(msg) log("DEBUG", msg, io.stdout) end
function M.info(msg)  log("INFO",  msg, io.stdout) end
function M.warn(msg)  log("WARN",  msg, io.stderr) end
function M.error(msg) log("ERROR", msg, io.stderr) end

return M
