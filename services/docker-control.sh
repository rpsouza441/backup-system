#!/bin/bash
# =============================================================================
# docker-control.sh - Controla containers Docker para backup
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# FUNÇÕES
# =============================================================================

stop_containers() {
    log "Parando containers Docker gracefully..."
    
    local containers
    containers=$(docker ps -q)
    
    if [ -z "$containers" ]; then
        log "Nenhum container rodando"
        return 0
    fi
    
    local timeout=${DOCKER_STOP_TIMEOUT:-10}
    
    if docker stop -t "$timeout" $containers >> "$LOG_FILE" 2>&1; then
        log "Containers parados com sucesso (graceful shutdown)"
    else
        log_warn "Alguns containers não pararam no timeout, verificando..."
        
        local still_running
        still_running=$(docker ps -q)
        
        if [ -n "$still_running" ]; then
            log "Forçando parada de containers que não responderam: $still_running"
            docker kill $still_running >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # Aguardar containers pararem completamente
    log "Aguardando finalização completa dos containers..."
    sleep 5
    
    return 0
}

start_containers() {
    log "Reiniciando containers Docker..."
    
    local all_containers
    all_containers=$(docker ps -a -q)
    
    if [ -z "$all_containers" ]; then
        log "Nenhum container encontrado para reiniciar"
        return 0
    fi
    
    if docker start $all_containers >> "$LOG_FILE" 2>&1; then
        log "Containers reiniciados com sucesso"
        return 0
    else
        log_error "Erro ao reiniciar alguns containers - verificar log"
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

ACTION="${1:-}"

case "$ACTION" in
    stop)
        stop_containers
        ;;
    start)
        start_containers
        ;;
    restart)
        stop_containers
        sleep 5
        start_containers
        ;;
    *)
        echo "Uso: $0 {stop|start|restart}"
        exit 1
        ;;
esac
