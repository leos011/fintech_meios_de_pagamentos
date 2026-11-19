#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Segurança da Informação - Infraestrutura Fintech (Grupo 2)
# ARQUIVO: scripts/check_integridade.sh
# DESCRIÇÃO: Auditoria periódica de integridade via SHA-256 para /etc/passwd,
#            /etc/shadow e regras salvas do firewall (/etc/iptables.rules).
# ==============================================================================

DIR_BASE="/var/lib/auditoria_fintech"
ARQUIVO_HASHES="$DIR_BASE/baseline_sha256.txt"
ARQUIVO_LOG="/var/log/integridade_fintech.log"
ALVOS=("/etc/passwd" "/etc/shadow" "/etc/iptables.rules")

if [[ $EUID -ne 0 ]]; then
   echo "[ERRO] Execute este script como superusuário (sudo ./check_integridade.sh)."
   exit 1
fi

mkdir -p "$DIR_BASE"
chmod 700 "$DIR_BASE"
touch "$ARQUIVO_LOG"
chmod 600 "$ARQUIVO_LOG"

gerar_baseline() {
    > "$ARQUIVO_HASHES"
    for arquivo in "${ALVOS[@]}"; do
        if [[ -f "$arquivo" ]]; then
            sha256sum "$arquivo" >> "$ARQUIVO_HASHES"
        else
            echo "[AVISO] Arquivo alvo não encontrado: $arquivo"
        fi
    done
    chmod 600 "$ARQUIVO_HASHES"
    DATA_ATUAL=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$DATA_ATUAL] [INFO] Linha de base SHA-256 gerada com sucesso." | tee -a "$ARQUIVO_LOG"
}

# Permite forçar recriação da base após manutenção autorizada
if [[ "$1" == "--iniciar" || ! -f "$ARQUIVO_HASHES" ]]; then
    gerar_baseline
    exit 0
fi

echo "=================================================================="
echo " AUDITORIA DE INTEGRIDADE SHA-256 - AMBIENTE FINTECH (GRUPO 2)"
echo "=================================================================="

HOUVE_VIOLACAO=0
DATA_ATUAL=$(date "+%Y-%m-%d %H:%M:%S")

while IFS= read -r linha; do
    HASH_ESPERADO=$(echo "$linha" | awk '{print $1}')
    CAMINHO_ARQUIVO=$(echo "$linha" | awk '{print $2}')

    if [[ ! -f "$CAMINHO_ARQUIVO" ]]; then
        echo "[ALERTA CRÍTICO] Arquivo monitorado removido: $CAMINHO_ARQUIVO"
        echo "[$DATA_ATUAL] [ALERTA] Arquivo removido: $CAMINHO_ARQUIVO" >> "$ARQUIVO_LOG"
        HOUVE_VIOLACAO=1
        continue
    fi

    HASH_ATUAL=$(sha256sum "$CAMINHO_ARQUIVO" | awk '{print $1}')

    if [[ "$HASH_ESPERADO" == "$HASH_ATUAL" ]]; then
        echo "[OK] Íntegro: $CAMINHO_ARQUIVO"
    else
        echo "------------------------------------------------------------------"
        echo "[ALERTA CRÍTICO] ALTERAÇÃO NÃO AUTORIZADA DETECTADA!"
        echo "  Arquivo      : $CAMINHO_ARQUIVO"
        echo "  Hash Original: $HASH_ESPERADO"
        echo "  Hash Atual   : $HASH_ATUAL"
        echo "------------------------------------------------------------------"
        echo "[$DATA_ATUAL] [ALERTA CRÍTICO] Integridade violada em $CAMINHO_ARQUIVO (Esperado: $HASH_ESPERADO | Atual: $HASH_ATUAL)" >> "$ARQUIVO_LOG"
        HOUVE_VIOLACAO=1
    fi
done < "$ARQUIVO_HASHES"

if [[ $HOUVE_VIOLACAO -eq 0 ]]; then
    echo "[$DATA_ATUAL] [OK] Verificação concluída sem alterações." >> "$ARQUIVO_LOG"
    exit 0
else
    echo "[AÇÃO NECESSÁRIA] Incidente registrado em $ARQUIVO_LOG."
    exit 2
fi