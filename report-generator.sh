#!/bin/bash
# =============================================================================
# report-generator.sh - Gerador de relatórios de backup
# =============================================================================
#
# Gera relatório com:
# 1. RESUMO EXECUTIVO no topo (para visualização rápida)
# 2. DETALHES expandidos abaixo
#
# Status do email:
# - SUCCESS: tudo OK
# - WARNING: alertas SMART ou problemas menores
# - CRITICAL: falhas de disco (status≠PASSED) ou erros graves
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações
source "${SCRIPT_DIR}/config/report.conf" 2>/dev/null || {
    echo "AVISO: report.conf não encontrado, usando defaults"
    LOG_DIR="/var/log/backup-system"
    REPORT_DIR="/var/log/backup-system/reports"
}

# Carregar módulos
source "${SCRIPT_DIR}/services/report/analyze-backup.sh"
source "${SCRIPT_DIR}/services/report/analyze-smart.sh"
source "${SCRIPT_DIR}/services/report/analyze-rsync.sh"
source "${SCRIPT_DIR}/services/report/analyze-disk.sh"
source "${SCRIPT_DIR}/services/report/send-email.sh"

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================
TODAY=$(date +%Y%m%d)
REPORT_FILE="${REPORT_DIR}/backup_report_${TODAY}.txt"
mkdir -p "$REPORT_DIR"

# =============================================================================
# ENCONTRAR LOGS DO DIA
# =============================================================================
find_today_logs() {
    BACKUP_LOG=$(find "$LOG_DIR" -name "backup_${TODAY}*.log" -type f 2>/dev/null | sort | tail -1)
    RSYNC_LOG=$(find "$LOG_DIR" -name "rsync_${TODAY}*.log" -type f 2>/dev/null | sort | tail -1)
    SMART_LOG="${LOG_DIR}/smart_latest.log"

    if [ ! -f "$SMART_LOG" ]; then
        SMART_LOG=$(find "$LOG_DIR" -name "smart_${TODAY}*.log" -type f 2>/dev/null | sort | tail -1)
    fi

    if [ ! -f "$SMART_LOG" ]; then
        SMART_LOG=$(find "$LOG_DIR" -name "smart_*.log" -type f 2>/dev/null | sort | tail -1)
    fi
}

# =============================================================================
# DETERMINAR STATUS GERAL
# =============================================================================
determine_overall_status() {
    OVERALL_STATUS="SUCCESS"
    
    # SMART com ERRO → CRITICAL
    if [ "$SMART_STATUS" = "ERROR" ]; then
        OVERALL_STATUS="CRITICAL"
        return
    fi
    
    # Backup falhou → CRITICAL
    if [ "$BACKUP_STATUS" = "MISSING" ] || [ "$BACKUP_STATUS" = "UNKNOWN" ]; then
        OVERALL_STATUS="CRITICAL"
        return
    fi
    
    # SMART com WARN → WARNING (mas não muda o título)
    # Rsync com erros → WARNING
    if [ "$RSYNC_STATUS" = "ERROR" ]; then
        OVERALL_STATUS="WARNING"
    fi
    
    # Disk quase cheio → WARNING
    if [ "$DISK_STATUS" = "WARN" ]; then
        OVERALL_STATUS="WARNING"
    fi
}

# =============================================================================
# GERAR RESUMO EXECUTIVO
# =============================================================================
generate_summary() {
    echo "================================================================="
    echo " RELATÓRIO DE BACKUP - $(date '+%d/%m/%Y')"
    echo " Servidor: $(hostname)"
    echo "================================================================="
    echo ""
    echo "=== RESUMO EXECUTIVO ==="
    echo ""
    
    # Backup
    local backup_icon="[OK]"
    [ "$BACKUP_STATUS" != "SUCCESS" ] && backup_icon="[ERROR]"
    echo "$backup_icon Backup: $BACKUP_STATUS ${BACKUP_DURATION:+($BACKUP_DURATION)}"
    
    # Storages
    echo "[OK] Storages: $STORAGE_STATUS montados"
    
    # OneDrive
    echo "[OK] OneDrive: $ONEDRIVE_STATUS acessíveis"
    
    # TAR
    local tar_icon="[OK]"
    [[ "$TAR_STATUS" == *"ERRO"* ]] && tar_icon="[ERROR]"
    [[ "$TAR_STATUS" == "N/A" ]] && tar_icon="[?]"
    echo "$tar_icon TAR: $TAR_STATUS"
    
    # SMART
    local smart_icon="[OK]"
    [ "$SMART_STATUS" = "ERROR" ] && smart_icon="[ERROR]"
    [ "$SMART_STATUS" = "WARN" ] && smart_icon="[WARN]"
    echo "$smart_icon SMART: $SMART_DISK_COUNT discos ($SMART_WARN_COUNT alertas, $SMART_ERROR_COUNT erros)"
    
    # Docker
    echo "[OK] Docker: $DOCKER_STATUS"
    
    echo ""
    echo "─────────────────────────────────────────"
    case "$OVERALL_STATUS" in
        SUCCESS)
            echo "STATUS GERAL: [OK] SUCESSO"
            ;;
        WARNING)
            echo "STATUS GERAL: [WARN] SUCESSO COM AVISOS"
            ;;
        CRITICAL)
            echo "STATUS GERAL: [CRITICAL] FALHA CRÍTICA"
            ;;
    esac
    echo "─────────────────────────────────────────"
}

# =============================================================================
# MAIN
# =============================================================================

echo "Gerando relatório de backup..."

# Encontrar logs
find_today_logs

# Executar análises
if [ -n "$BACKUP_LOG" ]; then
    analyze_backup "$BACKUP_LOG"
else
    BACKUP_STATUS="MISSING"
fi

analyze_smart "$SMART_LOG" || true
[ -n "$RSYNC_LOG" ] && analyze_rsync "$RSYNC_LOG" || true
analyze_disk

# Determinar status
determine_overall_status

# Gerar relatório
{
    generate_summary
    echo ""
    echo ""
    echo "=== DETALHES ==="
    
    [ -n "$BACKUP_LOG" ] && generate_backup_details "$BACKUP_LOG"
    generate_smart_details "$SMART_LOG"
    [ -n "$RSYNC_LOG" ] && generate_rsync_details "$RSYNC_LOG"
    generate_disk_details
    
    echo ""
    echo "================================================================="
    echo "Relatório gerado em: $(date '+%d/%m/%Y %H:%M:%S')"
    echo "================================================================="
} > "$REPORT_FILE"

echo "Relatório salvo em: $REPORT_FILE"

# Definir assunto do email
case "$OVERALL_STATUS" in
    SUCCESS)
        SUBJECT="[OK] Backup - $(hostname) - $(date +%d/%m)"
        ;;
    WARNING)
        SUBJECT="[WARN] Backup - $(hostname) - $(date +%d/%m)"
        ;;
    CRITICAL)
        SUBJECT="[ERROR] Backup - $(hostname) - $(date +%d/%m)"
        ;;
esac

# Enviar email
if send_email "$SUBJECT" "$REPORT_FILE"; then
    echo "Relatório enviado por email"
elif send_webhook "$SUBJECT" "$REPORT_FILE"; then
    echo "Relatório enviado via webhook"
else
    echo "Relatório salvo localmente (email/webhook não configurado)"
fi

# Limpeza de relatórios antigos
find "$REPORT_DIR" -name "backup_report_*.txt" -mtime +${REPORT_RETENTION_DAYS:-30} -delete 2>/dev/null

echo "Concluído!"
