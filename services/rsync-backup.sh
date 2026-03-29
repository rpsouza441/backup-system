#!/bin/bash
# =============================================================================
# rsync-backup.sh - Executa backup rsync
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================
DATA_SOURCE="${DATA_SOURCE:-/srv/DATA}"
DATA_DEST="${DATA_DEST:-/storage2/DATA}"
EXCLUDE_FILE="${RSYNC_EXCLUDE_FILE:-/storage2/DATA/EXCLUDE}"

# =============================================================================
# VERIFICAÇÕES
# =============================================================================

log "=========================================="
log "Iniciando rsync backup"
log "  Fonte: $DATA_SOURCE"
log "  Destino: $DATA_DEST"
log "=========================================="

# Verificar se destino está montado
dest_mount=$(dirname "$DATA_DEST")
if ! mountpoint -q "$dest_mount"; then
    log_error "$dest_mount não está montado - abortando rsync"
    exit 1
fi

# Verificar espaço em disco
if ! check_disk_space "$DATA_SOURCE" "$dest_mount"; then
    log_error "Espaço insuficiente - tentando limpeza emergencial"
    
    # Tentar limpeza de backups antigos (>3 dias)
    log "Tentando limpeza emergencial de backups antigos (>3 dias)..."
    find "$DATA_DEST" -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec rm -rf {} \;
    
    # Verificar novamente após limpeza
    if ! check_disk_space "$DATA_SOURCE" "$dest_mount"; then
        log_error "Mesmo após limpeza, espaço insuficiente! ABORTANDO"
        exit 1
    fi
    
    log "Limpeza bem-sucedida! Continuando backup..."
fi

# =============================================================================
# EXECUTAR RSYNC
# =============================================================================

# Criar diretório de destino
mkdir -p "$DATA_DEST"

# Variáveis para rsync
data_dia="$(date +%d)"
log_rsync="$LOG_DIR/rsync_$(date +%Y%m%d_%H%M%S).log"

# Opções do rsync
RSYNC_OPTS="--progress --force --ignore-errors --delete-excluded --compress --delete"
RSYNC_OPTS="$RSYNC_OPTS --backup --backup-dir=$DATA_DEST/$data_dia"
RSYNC_OPTS="$RSYNC_OPTS -a --no-o --no-g -v"
RSYNC_OPTS="$RSYNC_OPTS --log-file=$log_rsync"

# Adicionar exclude se arquivo existir
if [ -f "$EXCLUDE_FILE" ]; then
    RSYNC_OPTS="$RSYNC_OPTS --exclude-from=$EXCLUDE_FILE"
    log "Usando arquivo de exclusão: $EXCLUDE_FILE"
else
    log_warn "Arquivo de exclusão $EXCLUDE_FILE não encontrado"
fi

log "Iniciando rsync de $DATA_SOURCE para $DATA_DEST/Atual"

# Executar rsync
if rsync $RSYNC_OPTS "$DATA_SOURCE/" "$DATA_DEST/Atual"; then
    log_success "Rsync concluído"
    
    # Verificar erros no log do rsync
    if [ -f "$log_rsync" ] && grep -qi "error\|failed" "$log_rsync"; then
        log_warn "Possíveis erros encontrados no rsync - verificar $log_rsync"
    fi
else
    log_error "Falha no rsync"
    exit 1
fi

# =============================================================================
# ESTATÍSTICAS
# =============================================================================

if [ -f "$log_rsync" ]; then
    log "Coletando estatísticas do rsync..."
    
    files_transferred=$(grep -c " >f" "$log_rsync" 2>/dev/null || echo 0)
    files_deleted=$(grep -c "deleting" "$log_rsync" 2>/dev/null || echo 0)
    files_modified=$(grep -c "\.f" "$log_rsync" 2>/dev/null || echo 0)
    
    log "Rsync estatísticas:"
    log "  - Transferidos: $files_transferred arquivo(s)"
    log "  - Modificados: $files_modified arquivo(s)"
    log "  - Deletados: $files_deleted arquivo(s)"
    
    # Calcular tamanhos finais
    log "Calculando tamanhos finais..."
    size_source=$(du -sh "$DATA_SOURCE" | cut -f1)
    size_dest=$(du -sh "$DATA_DEST/Atual" | cut -f1)
    log "Tamanho Final Fonte: $size_source"
    log "Tamanho Final Destino: $size_dest"
fi

log "=========================================="
log "Rsync backup concluído"
log "=========================================="

exit 0
