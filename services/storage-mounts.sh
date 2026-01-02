#!/bin/bash
# =============================================================================
# storage-mounts.sh - Monta storages físicos por UUID
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# MAIN
# =============================================================================

log "=========================================="
log "Iniciando montagem de storages físicos"
log "=========================================="

MOUNT_ERRORS=0
MOUNT_SUCCESS=0

# Iterar sobre storages configurados
for storage_config in "${STORAGES[@]}"; do
    IFS=':' read -r uuid mount_point label critical <<< "$storage_config"
    
    log "Processando $label..."
    
    if mount_by_uuid "$uuid" "$mount_point" "$label"; then
        MOUNT_SUCCESS=$((MOUNT_SUCCESS + 1))
        record_mountcheck "$label" "$mount_point"
    else
        MOUNT_ERRORS=$((MOUNT_ERRORS + 1))
        
        if [ "$critical" = "1" ]; then
            log_error "Storage CRÍTICO $label falhou - abortando backup"
            exit 1
        else
            log_warn "Storage não-crítico $label falhou - continuando..."
        fi
    fi
done

log "=========================================="
log "Montagem de storages concluída"
log "  Sucesso: $MOUNT_SUCCESS"
log "  Erros: $MOUNT_ERRORS"
log "=========================================="

# Retorna código de erro se houver falhas não-críticas
exit $MOUNT_ERRORS
