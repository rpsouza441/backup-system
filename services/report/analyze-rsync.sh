#!/bin/bash
# =============================================================================
# analyze-rsync.sh - Analisa log do rsync
# =============================================================================

RSYNC_STATUS="OK"
RSYNC_ERROR_COUNT=0
RSYNC_TRANSFERRED=0
RSYNC_DELETED=0
RSYNC_TOTAL_SIZE=""

analyze_rsync() {
    local rsync_log="$1"
    
    if [ ! -f "$rsync_log" ]; then
        RSYNC_STATUS="N/A"
        return 1
    fi
    
    # Detectar erros
    local error_patterns=(
        "rsync: connection unexpectedly closed"
        "rsync error:"
        "Permission denied"
        "No space left on device"
        "Input/output error"
    )
    
    for pattern in "${error_patterns[@]}"; do
        local count
        count=$(grep -ci "$pattern" "$rsync_log" 2>/dev/null || true)
        count=${count:-0}
        # Garantir que é número
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            RSYNC_ERROR_COUNT=$((RSYNC_ERROR_COUNT + count))
        fi
    done
    
    if [ "$RSYNC_ERROR_COUNT" -gt 0 ]; then
        RSYNC_STATUS="ERROR"
    fi
    
    # Estatísticas - usar || true para evitar erro quando não encontra
    # Procura por " >f" (espaço > f) que indica arquivo transferido no formato padrão do rsync
    RSYNC_TRANSFERRED=$(grep -c " >f" "$rsync_log" 2>/dev/null || true)
    RSYNC_TRANSFERRED=${RSYNC_TRANSFERRED:-0}
    
    RSYNC_DELETED=$(grep -c "deleting" "$rsync_log" 2>/dev/null || true)
    RSYNC_DELETED=${RSYNC_DELETED:-0}
    
    # Tamanho total
    local total_line
    total_line=$(grep "total size is" "$rsync_log" 2>/dev/null | tail -1 || true)
    if [ -n "$total_line" ]; then
        local total_bytes
        total_bytes=$(echo "$total_line" | awk '{print $4}' | tr -cd '0-9')
        if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ] 2>/dev/null; then
            RSYNC_TOTAL_SIZE=$(awk "BEGIN{printf \"%.1f GB\", $total_bytes/1024/1024/1024}")
        fi
    fi
}

generate_rsync_details() {
    local rsync_log="$1"
    
    echo ""
    echo "ANÁLISE DO RSYNC"
    echo "================"
    
    if [ ! -f "$rsync_log" ]; then
        echo "Log rsync não encontrado"
        return
    fi
    
    echo "Log: $(basename "$rsync_log")"
    echo ""
    
    if [ "$RSYNC_ERROR_COUNT" -gt 0 ]; then
        echo "[ERROR] ERROS DETECTADOS: $RSYNC_ERROR_COUNT"
        grep -iE "error|failed|denied" "$rsync_log" 2>/dev/null | head -5 | while read -r line; do
            echo "  - $line"
        done
        echo ""
    else
        echo "[OK] Sem erros críticos"
    fi
    
    echo ""
    echo "ESTATÍSTICAS:"
    echo "  Arquivos transferidos: $RSYNC_TRANSFERRED"
    echo "  Arquivos deletados: $RSYNC_DELETED"
    
    # Tamanhos (novo)
    local size_src size_dest
    size_src=$(grep "Tamanho Final Fonte:" "$rsync_log" | tail -1 | cut -d':' -f2 | xargs)
    size_dest=$(grep "Tamanho Final Destino:" "$rsync_log" | tail -1 | cut -d':' -f2 | xargs)
    
    if [ -n "$size_src" ] && [ -n "$size_dest" ]; then
        echo "  Tamanho Fonte:   $size_src"
        echo "  Tamanho Destino: $size_dest"
    fi
    
    [ -n "$RSYNC_TOTAL_SIZE" ] && echo "  Tamanho Transferido: $RSYNC_TOTAL_SIZE"
    
    # Speedup
    local speedup
    speedup=$(grep "speedup is" "$rsync_log" 2>/dev/null | tail -1 | awk '{print $NF}' || true)
    if [ -n "$speedup" ]; then
        echo "  Speedup: ${speedup}x"
    fi
}
