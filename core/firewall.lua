local M = {}

local function run(cmd)
    local fh = io.popen(cmd .. " 2>&1")
    if not fh then return nil, "popen_failed" end
    local out = fh:read("*a")
    local ok, _, code = fh:close()
    return ok, out or "", code
end

local LOCAL_PORT_DEFAULT = 8123

local function chain_exists()
    local ok, out = run("iptables -t nat -L REDSOCKS -n 2>/dev/null || true")
    if ok and out and out:match("Chain REDSOCKS") then return true end
    return false
end

local function output_chain_linked()
    -- check if OUTPUT -j REDSOCKS exists
    local ok, out = run("iptables -t nat -C OUTPUT -p tcp -j REDSOCKS >/dev/null 2>&1 && echo yes || echo no")
    if out and out:match("yes") then return true end
    return false
end

local function add_if_missing(cmd_check, cmd_add)
    -- cmd_check should be a test that returns 0 when rule exists; we rely on shell return handling via `iptables -C`
    local ok, out = run(cmd_check .. " >/dev/null 2>&1 && echo yes || echo no")
    if ok and out:match("yes") then
        return true
    end
    return run(cmd_add)
end

-- Aplica regras de NAT e bloqueios mínimos (idempotente)
-- opts: local_port, block_udp (block dport 53 and 443), block_all_udp (block all UDP)
function M.apply(opts)
    opts = opts or {}
    local local_port = tonumber(opts.local_port) or LOCAL_PORT_DEFAULT
    local block_udp = opts.block_udp == true
    local block_all_udp = opts.block_all_udp == true

    -- 1) criar chain REDSOCKS se não existir
    if not chain_exists() then
        run("iptables -t nat -N REDSOCKS")
    end

    -- 2) limpar chain REDSOCKS para estado conhecido
    run("iptables -t nat -F REDSOCKS")

    -- 3) regras essenciais dentro da chain REDSOCKS
    run("iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN")
    run("iptables -t nat -A REDSOCKS -p tcp --dport 22 -j RETURN")
    run(string.format("iptables -t nat -A REDSOCKS -p tcp --dport %d -j RETURN", local_port))
    run(string.format("iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports %d", local_port))

    -- 4) anexar REDSOCKS a OUTPUT se ainda não estiver
    if not output_chain_linked() then
        run("iptables -t nat -A OUTPUT -p tcp -j REDSOCKS")
    end

    -- 5) bloqueios DNS/QUIC (UDP 53, UDP 443)
    if block_udp or block_all_udp then
        -- block UDP port 53
        add_if_missing("iptables -C OUTPUT -p udp --dport 53 -j REJECT",
                       "iptables -A OUTPUT -p udp --dport 53 -j REJECT")
        -- block UDP port 443 (QUIC)
        add_if_missing("iptables -C OUTPUT -p udp --dport 443 -j REJECT",
                       "iptables -A OUTPUT -p udp --dport 443 -j REJECT")
    end

    -- 6) opcional: bloquear todo UDP (cuidado)
    if block_all_udp then
        add_if_missing("iptables -C OUTPUT -p udp -j REJECT",
                       "iptables -A OUTPUT -p udp -j REJECT")
        -- but ensure we keep loopback allowed and possibly local services:
        -- make sure we don't block loopback (explicit rule to allow)
        -- If needed: insert an allow for loopback BEFORE the REJECT — it's safer to add a RETURN on nat chain,
        -- but for filter table we ensure loopback is permitted by default on many systems.
    end

    return true
end

-- Remove rules applied by the module (tenta reverter)
function M.remove(opts)
    opts = opts or {}
    local local_port = tonumber(opts.local_port) or LOCAL_PORT_DEFAULT

    -- remover jump OUTPUT -> REDSOCKS
    run("iptables -t nat -D OUTPUT -p tcp -j REDSOCKS >/dev/null 2>&1 || true")

    -- limpar e deletar chain REDSOCKS se existir
    if chain_exists() then
        run("iptables -t nat -F REDSOCKS >/dev/null 2>&1 || true")
        run("iptables -t nat -X REDSOCKS >/dev/null 2>&1 || true")
    end

    -- remover UDP blocks
    run("iptables -D OUTPUT -p udp --dport 53 -j REJECT >/dev/null 2>&1 || true")
    run("iptables -D OUTPUT -p udp --dport 443 -j REJECT >/dev/null 2>&1 || true")
    run("iptables -D OUTPUT -p udp -j REJECT >/dev/null 2>&1 || true")

    return true
end

function M.status()
    local ok, out = run("iptables -t nat -L REDSOCKS -n || true")
    local ok2, out2 = run("ss -ltnp sport = :" .. tostring(LOCAL_PORT_DEFAULT) .. " || lsof -iTCP:" .. tostring(LOCAL_PORT_DEFAULT) .. " -sTCP:LISTEN -P -n || true")
    local ok3, out3 = run("iptables -L OUTPUT -n --line-numbers || true")
    return { nat = out, listen = out2, output = out3 }
end

return M
