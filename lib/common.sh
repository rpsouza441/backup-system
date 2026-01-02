#!/bin/bash
# =============================================================================
# common.sh - Biblioteca de funções compartilhadas do sistema de backup
# =============================================================================

# Carregar configuração
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/backup.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERRO: Arquivo de configuração não encontrado: $CONFIG_FILE" >&2
    exit 1
fi

# =============================================================================
# VARIÁVEIS GLOBAIS
# =============================================================================
LOG_DIR="${LOG_DIR:-/var/log/backup-system}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log}"

# Criar diretório de log se não existir
mkdir -p "$LOG_DIR"

# =============================================================================
# FUNÇÕES DE LOG
# =============================================================================

# Log com timestamp
log() {
    local timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo "$timestamp $1" | tee -a "$LOG_FILE"
}

# Log de erro
log_error() {
    log "ERRO: $1"
}

# Log de aviso
log_warn() {
    log "AVISO: $1"
}

# Log de sucesso
log_success() {
    log "SUCESSO: $1"
}

# =============================================================================
# FUNÇÕES DE VERIFICAÇÃO DE UUID
# =============================================================================

# Verifica se UUID existe (com retry para boot)
check_uuid_exists() {
    local uuid=$1
    local max_attempts=${UUID_CHECK_ATTEMPTS:-6}
    local interval=${UUID_CHECK_INTERVAL:-10}
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if [ -n "$(blkid -U "$uuid" 2>/dev/null)" ]; then
            return 0
        fi
        
        if [ $attempt -eq 0 ]; then
            log "UUID $uuid não encontrado, aguardando dispositivo ficar disponível..."
        fi
        
        log "Tentativa $((attempt+1))/$max_attempts para UUID $uuid"
        sleep "$interval"
        attempt=$((attempt+1))
    done
    
    log_error "UUID $uuid não encontrado após $max_attempts tentativas"
    return 1
}

# Verifica se disco está montado por UUID
is_mounted_by_uuid() {
    local uuid=$1
    local device
    
    device=$(blkid -U "$uuid" 2>/dev/null)
    if [ -z "$device" ]; then
        return 1
    fi
    
    mount | grep -q "$device"
    return $?
}

# =============================================================================
# FUNÇÕES DE MOUNT
# =============================================================================

# Monta disco por UUID com verificação de integridade
mount_by_uuid() {
    local uuid=$1
    local mount_point=$2
    local label=${3:-$mount_point}
    local device

    log "Verificando UUID $uuid para $label..."

    if ! check_uuid_exists "$uuid"; then
        log_error "UUID $uuid não existe. Verifique se mudou!"
        return 1
    fi

    device=$(blkid -U "$uuid")
    log "UUID $uuid corresponde ao dispositivo $device"

    if is_mounted_by_uuid "$uuid"; then
        log "Dispositivo $device ($label) já está montado"
        return 0
    fi

    # Verificar integridade antes de montar
    log "Verificando integridade do disco $device..."
    fsck.ext4 -y "$device" >> "$LOG_FILE" 2>&1
    local fsck_result=$?

    if [ $fsck_result -eq 0 ] || [ $fsck_result -eq 1 ]; then
        log "Verificação concluída para $device"
    else
        log_warn "Problemas encontrados na verificação de $device"
    fi

    # Criar ponto de montagem se não existir
    mkdir -p "$mount_point"

    # Montar por UUID
    if mount UUID="$uuid" "$mount_point"; then
        log_success "Montado UUID $uuid em $mount_point ($label)"
        return 0
    else
        log_error "Falha ao montar UUID $uuid em $mount_point"
        return 1
    fi
}

# =============================================================================
# FUNÇÕES DE VERIFICAÇÃO
# =============================================================================

# Registra verificação de mount
record_mountcheck() {
    local name="$1"
    local path="$2"
    
    if [ -d "$path" ] && timeout 10 ls "$path" >/dev/null 2>&1; then
        log "[MOUNTCHK] $name OK $path"
        return 0
    else
        log "[MOUNTCHK] $name FAIL $path"
        return 1
    fi
}

# Verifica espaço em disco
check_disk_space() {
    local source_path="$1"
    local dest_path="$2"
    
    log "Verificando espaço em disco..."
    
    # Calcular tamanho do source (em KB)
    log "Calculando tamanho de $source_path..."
    local source_size_kb
    source_size_kb=$(du -sk "$source_path" 2>/dev/null | awk '{print $1}')
    
    if [ -z "$source_size_kb" ] || [ "$source_size_kb" -eq 0 ]; then
        log_warn "Não foi possível calcular tamanho de $source_path"
        return 0  # Continua mesmo assim
    fi
    
    local source_size_gb=$((source_size_kb / 1024 / 1024))
    log "Tamanho da fonte: ${source_size_gb}GB (${source_size_kb}KB)"
    
    # Calcular espaço disponível no destino (em KB)
    local available_kb
    available_kb=$(df "$dest_path" | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    log "Espaço disponível no destino: ${available_gb}GB"
    
    # Calcular espaço necessário (fonte + 50% de margem)
    local required_kb=$((source_size_kb * 3 / 2))  # 1.5x
    local required_gb=$((required_kb / 1024 / 1024))
    
    log "Espaço necessário (com margem 50%): ${required_gb}GB"
    
    if [ "$available_kb" -lt "$required_kb" ]; then
        log_error "Espaço insuficiente!"
        log "  Necessário: ${required_gb}GB"
        log "  Disponível: ${available_gb}GB"
        log "  Faltam: $((required_gb - available_gb))GB"
        return 1
    fi
    
    log "Verificação de espaço: OK (sobra de $((available_gb - required_gb))GB)"
    return 0
}

# Verifica saúde do mount rclone
check_rclone_health() {
    local mount_path="$1"
    local name="$2"
    local timeout_secs=${RCLONE_HEALTH_TIMEOUT:-30}
    
    log "Testando saúde do mount $name em $mount_path..."
    
    if timeout "$timeout_secs" ls "$mount_path" > /dev/null 2>&1; then
        log "Health check OK: $name respondendo normalmente"
        return 0
    else
        log_error "$name em $mount_path não responde (timeout ${timeout_secs}s)"
        return 1
    fi
}

# =============================================================================
# FUNÇÕES DE LOCK
# =============================================================================
LOCK_FILE="/var/run/backup.lock"

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_error "Backup já em execução (PID: $pid)"
            return 1
        else
            log_warn "Lock file obsoleto encontrado, removendo..."
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    log "Lock file criado (PID: $$)"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
    log "Lock file removido"
}

# Trap para liberar lock ao sair
setup_lock_trap() {
    trap 'release_lock' EXIT
}
