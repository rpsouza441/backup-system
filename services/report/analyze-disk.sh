#!/bin/bash
# =============================================================================
# analyze-disk.sh - Analisa espaço em disco
# =============================================================================

DISK_STATUS="OK"
DISK_CRITICAL_COUNT=0

analyze_disk() {
    # Verificar storages
    for i in 0 1 2 3; do
        local path="/storage${i}"
        if [ -d "$path" ]; then
            local usage
            usage=$(df "$path" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
            if [ -n "$usage" ] && [ "$usage" -ge 95 ]; then
                DISK_CRITICAL_COUNT=$((DISK_CRITICAL_COUNT + 1))
                DISK_STATUS="WARN"
            fi
        fi
    done
    
    if [ "$DISK_CRITICAL_COUNT" -gt 0 ]; then
        DISK_STATUS="WARN"
    fi
}

generate_disk_details() {
    echo ""
    echo "ESPAÇO EM DISCO"
    echo "==============="
    echo ""
    
    # Storages
    for i in 0 1 2 3; do
        local path="/storage${i}"
        if df "$path" >/dev/null 2>&1; then
            local info usage icon
            info=$(df -h "$path" | tail -1)
            usage=$(echo "$info" | awk '{print $5}' | tr -d '%')
            
            if [ "$usage" -ge 95 ]; then
                icon="[CRITICAL]"
            elif [ "$usage" -ge 90 ]; then
                icon="[WARN]"
            else
                icon="[OK]"
            fi
            
            echo "$icon Storage${i}: $(echo "$info" | awk '{print $3 "/" $2 " (" $5 ")"}')"
        fi
    done
    
    echo ""
    
    # OneDrive
    for mount in "/SERVER-BACKUP" "/JPG" "/IMMICH"; do
        if df "$mount" >/dev/null 2>&1; then
            local info
            info=$(df -h "$mount" | tail -1)
            echo "[OK] $(basename "$mount"): $(echo "$info" | awk '{print $3 "/" $2 " (" $5 ")"}')"
        fi
    done
    
    echo ""
    
    # Logs
    local log_size
    log_size=$(du -sh /var/log/backup-system 2>/dev/null | cut -f1)
    echo "Logs de backup: ${log_size:-N/A}"
}
