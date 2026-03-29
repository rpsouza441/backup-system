#!/bin/bash
# =============================================================================
# tar-backup.sh - Cria TAR comprimido e copia para OneDrive
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================
DATA_DEST="${DATA_DEST:-/storage2/DATA}"
TAR_SOURCE="$DATA_DEST/Atual"
BACKUP_PATH="/SERVER-BACKUP"
TAR_COPY_TIMEOUT="${TAR_COPY_TIMEOUT:-300}"
TAR_COPY_RETRIES="${TAR_COPY_RETRIES:-3}"

# =============================================================================
# VERIFICAÇÕES
# =============================================================================

log "=========================================="
log "Iniciando criação de TAR backup"
log "=========================================="

# Verificar se fonte existe
if [ ! -d "$TAR_SOURCE" ]; then
    log_error "Diretório fonte $TAR_SOURCE não existe"
    exit 1
fi

# Verificar se OneDrive está montado e saudável
if ! mountpoint -q "$BACKUP_PATH"; then
    log_error "OneDrive SERVER-BACKUP não está montado"
    exit 1
fi

if ! check_rclone_health "$BACKUP_PATH" "SERVER-BACKUP"; then
    log_error "OneDrive SERVER-BACKUP não está saudável"
    exit 1
fi

# =============================================================================
# CRIAR TAR
# =============================================================================

tar_name="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
tar_path_local="$DATA_DEST/$tar_name"
tar_path_backup="$BACKUP_PATH/$tar_name"

log "Criando TAR: $tar_name"
log "  Fonte: $TAR_SOURCE"
log "  Local: $tar_path_local"

if tar -czf "$tar_path_local" -C "$(dirname "$TAR_SOURCE")" "$(basename "$TAR_SOURCE")" >> "$LOG_FILE" 2>&1; then
    log_success "TAR criado em $tar_path_local"
    
    # Obter e logar tamanho
    tar_size=$(du -h "$tar_path_local" | cut -f1)
    log "Tamanho do TAR: $tar_size"
else
    log_error "Falha ao criar TAR"
    exit 1
fi

# =============================================================================
# VALIDAR INTEGRIDADE
# =============================================================================

log "Validando integridade do TAR..."

if tar -tzf "$tar_path_local" > /dev/null 2>&1; then
    log "TAR validado: integridade OK"
else
    log_error "TAR corrompido após criação!"
    rm -f "$tar_path_local"
    exit 1
fi

# =============================================================================
# COPIAR PARA ONEDRIVE
# =============================================================================

log "Copiando TAR para OneDrive..."

copy_attempt=0
copy_success=false

while [ $copy_attempt -lt $TAR_COPY_RETRIES ] && [ "$copy_success" = false ]; do
    copy_attempt=$((copy_attempt+1))
    log "Tentativa $copy_attempt/$TAR_COPY_RETRIES de copiar TAR para OneDrive..."
    
    # Copiar com timeout
    if timeout "$TAR_COPY_TIMEOUT" cp "$tar_path_local" "$tar_path_backup" 2>>"$LOG_FILE"; then
        log "TAR copiado com sucesso (tentativa $copy_attempt)"
        
        # Verificar tamanho identico
        size_local=$(stat -c%s "$tar_path_local" 2>/dev/null)
        size_backup=$(stat -c%s "$tar_path_backup" 2>/dev/null)
        
        if [ -n "$size_local" ] && [ -n "$size_backup" ] && [ "$size_local" -eq "$size_backup" ]; then
            log "Verificação OK: tamanhos correspondentes ($size_local bytes)"
            copy_success=true
        else
            log_error "Tamanhos diferentes! Local=$size_local Backup=$size_backup"
            rm -f "$tar_path_backup" 2>/dev/null
            [ $copy_attempt -lt $TAR_COPY_RETRIES ] && sleep 5
        fi
    else
        log_error "Timeout ou falha ao copiar TAR (tentativa $copy_attempt)"
        [ $copy_attempt -lt $TAR_COPY_RETRIES ] && sleep 5
    fi
done

if [ "$copy_success" = false ]; then
    log_error "Falha definitiva ao copiar TAR após $TAR_COPY_RETRIES tentativas"
    exit 1
fi

log "=========================================="
log "TAR backup concluído com sucesso"
log "  Arquivo: $tar_name"
log "  Tamanho: $tar_size"
log "=========================================="

exit 0
