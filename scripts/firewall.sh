#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Segurança da Informação - Infraestrutura Fintech (Grupo 2)
# ARQUIVO: scripts/firewall.sh
# DESCRIÇÃO: Firewall perimetral via Iptables com foco em APIs REST/HTTPS,
#            alta disponibilidade, anti-port scanning e rate-limiting.
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# 1. VARIÁVEIS DE AMBIENTE E REDE
# ------------------------------------------------------------------------------
IF_WAN="eth0"                  # Interface externa (Internet / Clientes API)
IF_LAN="lan0"                  # Interface interna (Rede corporativa)
REDE_LAN="10.10.20.0/24"         # Sub-rede interna autorizada
PORTA_API="443"                  # Porta HTTPS para transações bancárias (REST)
PORTA_SSH="2222"                 # Porta customizada do SSH (Hardening)
ARQUIVO_REGRAS="/etc/iptables.rules" # Base salva para auditoria SHA-256

# Garante execução como root
if [[ $EUID -ne 0 ]]; then
   echo "[ERRO] Execute este script como superusuário (sudo ./firewall.sh)."
   exit 1
fi

echo "[INFO] Iniciando aplicação das regras de firewall da Fintech..."

# ------------------------------------------------------------------------------
# 2. LIMPEZA DE REGRAS ANTERIORES
# ------------------------------------------------------------------------------
iptables -F
iptables -X
iptables -Z
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. POLÍTICAS PADRÃO (BLOQUEIO TOTAL POR PADRÃO)
# ------------------------------------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ------------------------------------------------------------------------------
# 4. TRÁFEGO DE LOOPBACK E CONEXÕES JÁ ESTABELECIDAS
# ------------------------------------------------------------------------------
# Permite comunicação interna do próprio sistema operacional
iptables -A INPUT -i lo -j ACCEPT

# Mantém sessões já validadas e relacionadas (Stateful Inspection)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Descarta imediatamente pacotes com estado inválido ou malformados
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# ------------------------------------------------------------------------------
# 5. PROTEÇÃO CONTRA VARREDURA DE PORTAS (PORT SCANNING)
# ------------------------------------------------------------------------------
# Bloqueia varreduras furtivas (NULL, XMAS, FIN e combinações inválidas de flags)
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

# ------------------------------------------------------------------------------
# 6. RATE-LIMITING E LIBERAÇÃO DE SERVIÇOS DA FINTECH
# ------------------------------------------------------------------------------
# 6.1 Acesso Administrativo SSH (Porta 2222) com proteção contra força bruta
# Bloqueia por 60s qualquer IP que tentar mais de 4 novas conexões em 1 minuto
iptables -A INPUT -p tcp --dport "$PORTA_SSH" -m conntrack --ctstate NEW \
  -m recent --set --name BLOQUEIO_SSH
iptables -A INPUT -p tcp --dport "$PORTA_SSH" -m conntrack --ctstate NEW \
  -m recent --update --seconds 60 --hitcount 5 --name BLOQUEIO_SSH -j DROP
iptables -A INPUT -p tcp --dport "$PORTA_SSH" -m conntrack --ctstate NEW -j ACCEPT

# 6.2 API Bancária REST/HTTPS (Porta 443) com controle de taxa por IP de origem
# Usa hashlimit (srcip) para mitigar SYN/HTTP Flood sem derrubar clientes legítimos
iptables -A INPUT -p tcp --dport "$PORTA_API" -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit-above 30/sec --hashlimit-burst 60 \
  --hashlimit-mode srcip --hashlimit-name LIMIT_API_HTTPS -j DROP
iptables -A INPUT -p tcp --dport "$PORTA_API" -m conntrack --ctstate NEW -j ACCEPT

# 6.3 Diagnóstico de rede controlado (ICMP Ping limitado a 2 pacotes/s na LAN)
iptables -A INPUT -s "$REDE_LAN" -p icmp --icmp-type echo-request \
  -m limit --limit 2/sec --limit-burst 4 -j ACCEPT

# ------------------------------------------------------------------------------
# 7. PERSISTÊNCIA PARA AUDITORIA DE INTEGRIDADE (MÓDULO 3)
# ------------------------------------------------------------------------------
iptables-save > "$ARQUIVO_REGRAS"
chmod 600 "$ARQUIVO_REGRAS"

echo "[OK] Firewall ativado com sucesso. Regras salvas em $ARQUIVO_REGRAS."