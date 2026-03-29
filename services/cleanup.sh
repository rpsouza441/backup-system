#!/bin/bash
# =============================================================================
# cleanup.sh - Limpa backups e logs antigos
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================
DATA_DEST="${DATA_DEST:-/storage2/DATA}"
BACKUP_PATH="/SERVER-BACKUP"
TAR_RETENTION_DAYS="${TAR_RETENTION_DAYS:-7}"
DAILY_BACKUP_RETENTION="${DAILY_BACKUP_RETENTION:-5}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-60}"

# =============================================================================
# MAIN
# =============================================================================

log "=========================================="
log "Executando limpeza de backups antigos"
log "=========================================="

total_removed=0

# -----------------------------------------------------------------------------
# Limpar TARs locais
# -----------------------------------------------------------------------------
log "Limpando TARs locais com mais de $TAR_RETENTION_DAYS dias..."
removed_local=0

if [ -d "$DATA_DEST" ]; then
    while IFS= read -r file; do
        if rm -f "$file" 2>>"$LOG_FILE"; then
            log "[CLEANUP] Removido TAR local: $(basename "$file")"
            removed_local=$((removed_local+1))
        else
            log_warn "[CLEANUP] Erro ao remover: $(basename "$file")"
        fi
    done < <(find "$DATA_DEST" -maxdepth 1 -name "backup_*.tar.gz" -mtime +$TAR_RETENTION_DAYS -print 2>/dev/null)
fi

log "TARs locais removidos: $removed_local"
total_removed=$((total_removed + removed_local))

# -----------------------------------------------------------------------------
# Limpar TARs no OneDrive
# -----------------------------------------------------------------------------
log "Limpando TARs no OneDrive com mais de $TAR_RETENTION_DAYS dias..."
removed_backup=0

if [ -d "$BACKUP_PATH" ] && mountpoint -q "$BACKUP_PATH"; then
    while IFS= read -r file; do
        if timeout 60 rm -f "$file" 2>>"$LOG_FILE"; then
            log "[CLEANUP] Removido TAR backup: $(basename "$file")"
            removed_backup=$((removed_backup+1))
        else
            log_warn "[CLEANUP] Erro/Timeout ao remover: $(basename "$file")"
        fi
    done < <(find "$BACKUP_PATH" -maxdepth 1 -name "backup_*.tar.gz" -mtime +$TAR_RETENTION_DAYS -print 2>/dev/null)
else
    log_warn "OneDrive SERVER-BACKUP não montado - pulando limpeza de TARs"
fi

log "TARs OneDrive removidos: $removed_backup"
total_removed=$((total_removed + removed_backup))

# -----------------------------------------------------------------------------
# Limpar pastas diárias do rsync
# -----------------------------------------------------------------------------
log "Limpando pastas diárias com mais de $DAILY_BACKUP_RETENTION dias..."
removed_daily=0

if [ -d "$DATA_DEST" ]; then
    while IFS= read -r folder; do
        if rm -rf "$folder" 2>>"$LOG_FILE"; then
            log "[CLEANUP] Removida pasta diária: $(basename "$folder")"
            removed_daily=$((removed_daily+1))
        fi
    done < <(find "$DATA_DEST" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended \
        -regex '.*/[0-9]{1,2}' -mtime +$DAILY_BACKUP_RETENTION -print 2>/dev/null)
fi

log "Pastas diárias removidas: $removed_daily"
total_removed=$((total_removed + removed_daily))

# -----------------------------------------------------------------------------
# Limpar logs antigos
# -----------------------------------------------------------------------------
log "Limpando logs com mais de $LOG_RETENTION_DAYS dias..."
removed_logs=0

if [ -d "$LOG_DIR" ]; then
    while IFS= read -r file; do
        if rm -f "$file" 2>>"$LOG_FILE"; then
            log "[CLEANUP] Removido log: $(basename "$file")"
            removed_logs=$((removed_logs+1))
        fi
    done < <(find "$LOG_DIR" -type f -name "*.log" -mtime +$LOG_RETENTION_DAYS -print 2>/dev/null)
fi

log "Logs removidos: $removed_logs"
total_removed=$((total_removed + removed_logs))

# -----------------------------------------------------------------------------
# Resumo
# -----------------------------------------------------------------------------
log "=========================================="
log "Limpeza concluída"
log "  TARs locais: $removed_local"
log "  TARs OneDrive: $removed_backup"
log "  Pastas diárias: $removed_daily"
log "  Logs: $removed_logs"
log "  Total removido: $total_removed item(s)"
log "=========================================="

exit 0
