local env = require("core.env")
local pyproxy = require("core.pyproxy")
local proxylist = require("core.proxylist")
local nettest = require("core.nettest")
local log = require("core.log")
local configgen = require("core.configgen")
local control = require("core.control")
local firewall = require("core.firewall")
local iptables = require("core.iptables")
local status = require("core.status")

-- Configurar log
log.set_level("INFO")

-- Flags especiais primeiro
for _, v in ipairs(arg) do
    if v == "--restore-iptables" then
        log.warn("Flag --restore-iptables detectada, pulando fluxo normal...")
        local ok, info = iptables.restore_interactive()
        if not ok then
            log.error("Falha ao restaurar iptables: " .. tostring(info))
            os.exit(1)
        end
        log.info("iptables restaurado com sucesso: " .. tostring(info))
        os.exit(0)
    elseif v == "--reset-iptables" then
        log.warn("Flag --reset-iptables detectada, resetando iptables para estado inicial...")
        local ok, info = iptables.reset()
        if not ok then
            log.error("Falha ao resetar iptables: " .. tostring(info))
            os.exit(1)
        end
        log.info(info)
        os.exit(0)
    elseif v == "--status" then
        log.info("Flag --status detectada, mostrando informações do OrpheonGuardND...")

        -- Redsocks
        local r_ok, r_out = status.check_redsocks(8123)
        if r_ok then
            log.info("Redsocks rodando na porta 8123: " .. r_out)
        else
            log.warn("Redsocks não está rodando na porta 8123.")
        end

        -- Proxy atual
        local proxy, perr = status.current_proxy("/etc/redsocks.conf")
        if proxy then
            log.info("Proxy em uso: " .. proxy)
        else
            log.warn("Proxy atual não detectado: " .. tostring(perr))
        end

        -- iptables
        local summary = status.iptables_summary()
        log.info("Chain REDSOCKS:\n" .. summary.redsocks_chain)
        log.info("Chain OUTPUT:\n" .. summary.output_chain)

        os.exit(0)
    end
end

-- Sempre faz backup do iptables no início
local bok, binfo = iptables.backup()
if bok then
    log.info("Backup do iptables realizado.")
else
    log.error("Falha ao realizar backup do iptables: " .. tostring(binfo))
    os.exit(1) -- aborta se backup falhar
end

-- Carrega variáveis do .env
env.load(".env")

-- Garante que PROXY esteja definido
local proxy_url, err = env.require("PROXY")
if not proxy_url then
    log.error("Variável PROXY não definida: " .. tostring(err))
    os.exit(1)
end

local PROXY_FILE = "proxy.txt"

-- Verifica argumentos
local reset = false
for _, v in ipairs(arg) do
    if v == "-r" or v == "--reset" then
        reset = true
    end
end

if reset and os.remove(PROXY_FILE) then
    log.warn("Flag -r detectada: proxy.txt foi removido para resetar a lista.")
end

-- Garante que proxy.txt exista
local f = io.open(PROXY_FILE, "r")
if f then
    f:close()
    log.info("proxy.txt já existe, lendo arquivo local.")
else
    log.info("proxy.txt não encontrado, buscando proxies da URL: " .. proxy_url)
    local proxies, perr = pyproxy.fetch(proxy_url)
    if not proxies then
        log.error("Falha ao buscar proxies: " .. tostring(perr))
        os.exit(1)
    end

    local ok, count_or_err = pyproxy.write(PROXY_FILE, proxies)
    if not ok then
        log.error("Falha ao salvar proxy.txt: " .. tostring(count_or_err))
        os.exit(1)
    end
    log.info("proxy.txt criado com " .. tostring(count_or_err) .. " proxies.")
end

-- Carregar proxies
local proxies, perr = proxylist.load(PROXY_FILE)
if not proxies then
    log.error("Falha ao carregar proxies: " .. tostring(perr))
    os.exit(1)
end
log.info("Total de proxies carregados: " .. tostring(#proxies))

if #proxies == 0 then
    log.error("Nenhum proxy válido em " .. PROXY_FILE)
    os.exit(1)
end

-- Testar proxies
log.info("Iniciando testes de conectividade...")
local results = nettest.test_all(proxies, { timeout = 3, concurrency = 50 })
log.info("Proxies funcionais: " .. tostring(#results))

if #results == 0 then
    log.error("Nenhum proxy funcional encontrado.")
    os.exit(1)
end

-- Filtrar proxies com latência aceitável (0 < latency <= 0.5s)
local filtered = {}
for _, r in ipairs(results) do
    if r.latency > 0 and r.latency <= 0.5 then
        table.insert(filtered, r)
    end
end

log.info("Proxies dentro da latência aceitável (<= 0.5s): " .. tostring(#filtered))

if #filtered == 0 then
    log.error("Nenhum proxy ficou dentro do limite de latência (<= 0.5s).")
    os.exit(1)
end

-- Sobrescreve proxy.txt apenas com os bons
local proxy_lines = {}
for _, r in ipairs(filtered) do
    table.insert(proxy_lines, string.format("%s:%d", r.host, r.port))
end

local f, werr = io.open(PROXY_FILE, "w")
if not f then
    log.error("Falha ao sobrescrever proxy.txt: " .. tostring(werr))
    os.exit(1)
end
f:write(table.concat(proxy_lines, "\n") .. "\n")
f:close()
log.info("proxy.txt atualizado com " .. tostring(#filtered) .. " proxies de alta qualidade.")

-- Log dos proxies bons
for i, r in ipairs(filtered) do
    log.info(string.format("OK %3d) %s:%d latency=%.3fs", i, r.host, r.port, r.latency))
end

-- Seleciona apenas o melhor proxy (primeiro da lista filtrada)
local best_proxy = filtered[1]
if not best_proxy then
    log.error("Nenhum proxy disponível para gerar redsocks.conf")
    os.exit(1)
end

-- Gera config do redsocks com um único proxy
local ok, path = configgen.generate(best_proxy, { path = "/etc/redsocks.conf", local_port = 8123 })
if not ok then
    log.error("Falha ao gerar redsocks.conf: " .. tostring(path))
    os.exit(1)
end
log.info("redsocks.conf gerado em " .. path .. " usando proxy " ..
    best_proxy.host .. ":" .. best_proxy.port .. " (latência " .. best_proxy.latency .. "s)")

-- Reinicia redsocks
local restarted, out = control.restart(path, 8123)
if not restarted then
    log.error("Falha ao reiniciar redsocks: " .. tostring(out))
    os.exit(1)
end
log.info("Redsocks reiniciado com sucesso na porta 8123.")

-- Aplica firewall (bloqueia TODO o UDP + redireciona TCP)
local okfw, fwerr = pcall(firewall.apply, { local_port = 8123, block_all_udp = true })
if not okfw then
    log.error("Erro ao aplicar firewall (pcall): " .. tostring(fwerr))
    os.exit(1)
end
log.info("Regras de firewall aplicadas (todo TCP de saída via redsocks, todo UDP bloqueado).")
