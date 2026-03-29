#!/bin/bash
# =============================================================================
# backup-orchestrator.sh - Orquestrador principal do sistema de backup
# =============================================================================
#
# Este script coordena todos os serviços de backup na ordem correta:
# 1. Montar storages físicos
# 2. Gerar relatório SMART
# 3. Verificar mounts OneDrive (systemd)
# 4. Parar containers Docker
# 5. Executar rsync backup
# 6. Criar TAR backup
# 7. Executar limpeza
# 8. Reiniciar containers Docker
# 9. Gerar resumo final
#
# =============================================================================

set -e

# Diretório base do sistema
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar biblioteca comum
source "${SCRIPT_DIR}/lib/common.sh"

# Definir arquivo de log para esta execução
export LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Medição monotônica da duração da execução
SECONDS=0

# =============================================================================
# FUNÇÕES DO ORQUESTRADOR
# =============================================================================

run_service() {
    local cmd_string="$1"
    local allow_failure="${2:-false}"
    
    # Extract filename (first word)
    local service_name=$(echo "$cmd_string" | awk '{print $1}')
    # Extract arguments (everything else)
    local service_args=$(echo "$cmd_string" | awk '{$1=""; print $0}' | xargs)
    
    local service_path="${SCRIPT_DIR}/services/${service_name}"
    
    log "Executando serviço: $service_name $service_args"
    
    if [ ! -x "$service_path" ]; then
        log_error "Serviço não encontrado ou não executável: $service_path"
        [ "$allow_failure" = "true" ] && return 1 || exit 1
    fi
    
    if "$service_path" $service_args; then
        log_success "$service_name concluído"
        return 0
    else
        log_error "$service_name falhou"
        [ "$allow_failure" = "true" ] && return 1 || exit 1
    fi
}

verify_onedrive_mounts() {
    log "Verificando mounts OneDrive (systemd)..."
    
    local mount_errors=0
    
    # Verificar SERVER-BACKUP (crítico)
    if systemctl is-active --quiet rclone-onedrive@SERVER-BACKUP.service 2>/dev/null; then
        if record_mountcheck "SERVER-BACKUP" "/SERVER-BACKUP"; then
            log "OneDrive SERVER-BACKUP: OK"
        else
            log_error "OneDrive SERVER-BACKUP: montado mas não responde"
            mount_errors=$((mount_errors + 1))
        fi
    else
        log_error "OneDrive SERVER-BACKUP: serviço não ativo"
        mount_errors=$((mount_errors + 1))
    fi
    
    # Verificar JPG (não-crítico)
    if systemctl is-active --quiet rclone-onedrive-jpb.service 2>/dev/null; then
        record_mountcheck "JPG" "/JPG" || true
        log "OneDrive JPG: OK"
    else
        log_warn "OneDrive JPG: serviço não ativo"
    fi
    
    # Verificar IMMICH (não-crítico)
    if systemctl is-active --quiet rclone-onedrive-immich.service 2>/dev/null; then
        record_mountcheck "IMMICH" "/IMMICH" || true
        log "OneDrive IMMICH: OK"
    else
        log_warn "OneDrive IMMICH: serviço não ativo"
    fi
    
    return $mount_errors
}

generate_summary() {
    log "=================================="
    log "Resumo da execução:"
    log "=================================="
    
    # Mostrar mapeamento final
    log "Storages montados:"
    mount | grep -E "(storage[0-9])" | while read -r line; do
        log "  $line"
    done
    
    # Listar montagens OneDrive
    log "Montagens OneDrive:"
    mount | grep -E "(SERVER-BACKUP|JPG|IMMICH)" | while read -r line; do
        log "  $line"
    done
    
    # Verificar acesso OneDrive
    log "Verificação de acesso OneDrive:"
    for path in "/SERVER-BACKUP" "/JPG" "/IMMICH"; do
        if [ -d "$path" ] && timeout 5 ls "$path" > /dev/null 2>&1; then
            log "  ✓ $path - ACESSÍVEL"
        else
            log "  ✗ $path - INACESSÍVEL ou não montado"
        fi
    done
    
    # Espaço em disco
    log "Espaço em disco atual:"
    df -h | grep -E "(storage[0-9]|SERVER-BACKUP|JPG|IMMICH|Filesystem)" >> "$LOG_FILE" 2>&1
}

# =============================================================================
# MAIN
# =============================================================================

log "=================================="
log "Iniciando Sistema de Backup Modular"
log "Versão: 2.0"
log "Data: $(date)"
log "=================================="

# Aguardar dispositivos ficarem disponíveis (boot)
sleep 30

# Adquirir lock
if ! acquire_lock; then
    exit 1
fi
setup_lock_trap

# Variável para rastrear erros
BACKUP_ERRORS=0

# -----------------------------------------------------------------------------
# 1. Montar storages físicos
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 1: Montagem de Storages"
if ! run_service "storage-mounts.sh" "true"; then
    BACKUP_ERRORS=$((BACKUP_ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# 2. Gerar relatório SMART
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 2: Verificação SMART"
run_service "smart-check.sh" "true" || true

# -----------------------------------------------------------------------------
# 3. Verificar mounts OneDrive
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 3: Verificação OneDrive"
if ! verify_onedrive_mounts; then
    log_error "Problemas com OneDrive SERVER-BACKUP - TAR não será criado"
    BACKUP_ERRORS=$((BACKUP_ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# 4. Parar containers Docker
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 4: Parando Docker"
run_service "docker-control.sh stop" "true" || true

# -----------------------------------------------------------------------------
# 5. Executar rsync backup
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 5: Rsync Backup"
if ! run_service "rsync-backup.sh" "true"; then
    BACKUP_ERRORS=$((BACKUP_ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# 6. Criar TAR backup (apenas se OneDrive OK)
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 6: TAR Backup"
if mountpoint -q "/SERVER-BACKUP" 2>/dev/null; then
    if ! run_service "tar-backup.sh" "true"; then
        BACKUP_ERRORS=$((BACKUP_ERRORS + 1))
    fi
else
    log_warn "Pulando TAR - OneDrive não montado"
fi

# -----------------------------------------------------------------------------
# 7. Executar limpeza
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 7: Limpeza"
run_service "cleanup.sh" "true" || true

# -----------------------------------------------------------------------------
# 8. Reiniciar containers Docker
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 8: Reiniciando Docker"
# Aguardar antes de reiniciar
sleep 5
run_service "docker-control.sh start" "true" || true

# -----------------------------------------------------------------------------
# 9. Resumo final
# -----------------------------------------------------------------------------
log ""
log ">>> FASE 9: Resumo"
generate_summary

# Status final
if [ $BACKUP_ERRORS -eq 0 ]; then
    log "STATUS: SUCESSO - Backup concluído sem erros críticos"
    exit_code=0
else
    log "STATUS: AVISO/ERRO - Backup concluído com $BACKUP_ERRORS problema(s)"
    exit_code=1
fi

elapsed=$SECONDS
log "DURAÇÃO REAL: ${elapsed}s ($((elapsed/60))m $((elapsed%60))s)"
log "Log detalhado salvo em: $LOG_FILE"
log "Script finalizado em $(date)"

exit $exit_code
