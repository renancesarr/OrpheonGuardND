local proxylist = require("core.proxylist")
local nettest = require("core.nettest")
local log = require("core.log")

-- Configura log para INFO (use DEBUG se quiser ver todos os detalhes)
log.set_level("INFO")

local PROXY_FILE = "proxy.txt"

-- Carrega proxies
local proxies, err = proxylist.load(PROXY_FILE)
if not proxies then
    log.error("Falha ao carregar proxies: " .. tostring(err))
    os.exit(1)
end

log.info("Total de proxies carregados: " .. tostring(#proxies))
if #proxies == 0 then
    log.error("Nenhum proxy encontrado em " .. PROXY_FILE)
    os.exit(1)
end

-- Testa proxies
log.info("Iniciando testes de conectividade...")
local results = nettest.test_all(proxies, { timeout = 3, concurrency = 50 })
log.info("Proxies funcionais: " .. tostring(#results))

if #results == 0 then
    log.error("Nenhum proxy funcional encontrado.")
    os.exit(1)
end

-- Mostrar todos os resultados em ordem
log.info("----- RESULTADOS ORDENADOS POR LATÊNCIA -----")
for i, r in ipairs(results) do
    log.info(string.format("%3d) %s:%d  latency=%.3fs", i, r.host, r.port, r.latency))
end

-- Selecionar top 10%
local top_n = math.max(1, math.floor(#results * 0.10))
log.info(string.format("Selecionando top %d (%.0f%%) proxies...", top_n, (#results > 0 and (top_n/#results*100) or 0)))

for i = 1, top_n do
    local r = results[i]
    log.info(string.format("TOP %d) %s:%d  latency=%.3fs", i, r.host, r.port, r.latency))
end
