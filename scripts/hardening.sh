#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Segurança da Informação - Infraestrutura Fintech (Grupo 2)
# ARQUIVO: scripts/hardening.sh
# DESCRIÇÃO: Hardening do Ubuntu Server (atualizações, remoção de pacotes
#            inseguros, permissões em diretórios críticos e parâmetros sysctl).
# ==============================================================================

set -e

if [[ $EUID -ne 0 ]]; then
   echo "[ERRO] Execute este script como superusuário (sudo ./hardening.sh)."
   exit 1
fi

echo "[INFO] Iniciando hardening do Ubuntu Server (Fintech)..."

# ------------------------------------------------------------------------------
# 1. ATUALIZAÇÃO DE SEGURANÇA DO SISTEMA
# ------------------------------------------------------------------------------
echo "[1/4] Atualizando listas e pacotes de segurança..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ------------------------------------------------------------------------------
# 2. REMOÇÃO DE PACOTES E SERVIÇOS LEGADOS INSEGUROS
# ------------------------------------------------------------------------------
echo "[2/4] Removendo pacotes desnecessários ou com protocolos em texto claro..."
PACOTES_INSEGUROS=("telnet" "rsh-client" "nis" "talk" "ftp" "xinetd")

for pacote in "${PACOTES_INSEGUROS[@]}"; do
    if dpkg -l | grep -qw "$pacote"; then
        apt-get purge -y "$pacote"
        echo "  -> Pacote removido: $pacote"
    fi
done
apt-get autoremove -y

# ------------------------------------------------------------------------------
# 3. AJUSTE DE PERMISSÕES EM DIRETÓRIOS E ARQUIVOS CRÍTICOS
# ------------------------------------------------------------------------------
echo "[3/4] Restringindo permissões em /etc/ e /var/log/..."

# Arquivos de identidade e credenciais
chown root:root /etc/passwd /etc/group
chmod 644 /etc/passwd /etc/group

chown root:shadow /etc/shadow /etc/gshadow
chmod 640 /etc/shadow /etc/gshadow

# Proteção da configuração do SSH (se já estiver copiada)
if [[ -f /etc/ssh/sshd_config ]]; then
    chown root:root /etc/ssh/sshd_config
    chmod 600 /etc/ssh/sshd_config
fi

# Restrição de acesso aos logs de auditoria do sistema
chown -R root:adm /var/log
chmod 750 /var/log
find /var/log -type f -exec chmod 640 {} +

# ------------------------------------------------------------------------------
# 4. ENDURECIMENTO DE PILHA TCP/IP NO KERNEL (ALTA DISPONIBILIDADE)
# ------------------------------------------------------------------------------
echo "[4/4] Aplicando parâmetros de proteção de rede no sysctl..."
cat << 'EOF' > /etc/sysctl.d/99-fintech-hardening.conf
# Proteção contra SYN Flood (mantém disponibilidade das APIs HTTPS)
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048

# Proteção contra IP Spoofing (Reverse Path Filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignora redirecionamentos ICMP e pacotes source-routed
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0

# Registra pacotes suspeitos/martians no log do kernel
net.ipv4.conf.all.log_martians = 1
EOF

sysctl --system > /dev/null

echo "[OK] Hardening concluído com sucesso."