#!/bin/bash
# =============================================================================
# analyze-smart.sh - Analisa saúde dos discos (SMART)
# Retorna: SMART_STATUS (OK/WARN/ERROR), contagem de alertas
# =============================================================================

SMART_STATUS="OK"
SMART_DISK_COUNT=0
SMART_WARN_COUNT=0
SMART_ERROR_COUNT=0
SMART_DETAILS=""

analyze_smart() {
    local smart_log="${1:-/var/log/backup-system/smart_latest.log}"
    
    if [ ! -f "$smart_log" ]; then
        SMART_STATUS="N/A"
        return 1
    fi
    
    # Processar cada linha [SMART]
    while IFS= read -r line; do
        SMART_DISK_COUNT=$((SMART_DISK_COUNT + 1))
        
        local dev status realloc pending offline_unc
        dev=$(echo "$line" | sed -n 's/.*dev=\([^ ]*\).*/\1/p')
        status=$(echo "$line" | sed -n 's/.*status=\([^ ]*\).*/\1/p')
        realloc=$(echo "$line" | sed -n 's/.*realloc=\([0-9]*\).*/\1/p')
        pending=$(echo "$line" | sed -n 's/.*pending=\([0-9]*\).*/\1/p')
        offline_unc=$(echo "$line" | sed -n 's/.*offline_unc=\([0-9]*\).*/\1/p')
        
        # Determinar severidade
        # ERRO: status≠PASSED/OK ou realloc>0 (setores realocados = dano permanente)
        # WARN: outros alertas (pending, timeout, etc)
        
        local is_error=false
        local is_warn=false
        
        if [ "$status" != "PASSED" ] && [ "$status" != "OK" ]; then
            is_error=true
        elif [ "${realloc:-0}" -gt 0 ]; then
            is_error=true
        elif [ "${pending:-0}" -gt 0 ] || [ "${offline_unc:-0}" -gt 0 ]; then
            is_warn=true
        fi
        
        if [ "$is_error" = true ]; then
            SMART_ERROR_COUNT=$((SMART_ERROR_COUNT + 1))
            SMART_STATUS="ERROR"
        elif [ "$is_warn" = true ]; then
            SMART_WARN_COUNT=$((SMART_WARN_COUNT + 1))
            if [ "$SMART_STATUS" = "OK" ]; then
                SMART_STATUS="WARN"
            fi
        fi
        
    done < <(grep "^\[SMART\]" "$smart_log")
    
    return 0
}

# Gerar seção detalhada
generate_smart_details() {
    local smart_log="${1:-/var/log/backup-system/smart_latest.log}"
    
    echo ""
    echo "SAÚDE DOS DISCOS (SMART)"
    echo "========================"
    
    if [ ! -f "$smart_log" ]; then
        echo "Log SMART não encontrado"
        return
    fi
    
    while IFS= read -r line; do
        local dev type status temp realloc pending offline_unc alerts notes
        dev=$(echo "$line" | sed -n 's/.*dev=\([^ ]*\).*/\1/p')
        type=$(echo "$line" | sed -n 's/.*type=\([^ ]*\).*/\1/p')
        status=$(echo "$line" | sed -n 's/.*status=\([^ ]*\).*/\1/p')
        temp=$(echo "$line" | sed -n 's/.*temp=\([^ ]*\).*/\1/p')
        realloc=$(echo "$line" | sed -n 's/.*realloc=\([0-9]*\).*/\1/p')
        pending=$(echo "$line" | sed -n 's/.*pending=\([0-9]*\).*/\1/p')
        offline_unc=$(echo "$line" | sed -n 's/.*offline_unc=\([0-9]*\).*/\1/p')
        alerts=$(echo "$line" | sed -n 's/.*alerts=\[\([^]]*\)\].*/\1/p')
        notes=$(echo "$line" | sed -n 's/.*note=\[\([^]]*\)\].*/\1/p')
        
        # Determinar ícone
        local icon="[OK]"
        if [ "$status" != "PASSED" ] && [ "$status" != "OK" ]; then
            icon="[ERROR]"
        elif [ "${realloc:-0}" -gt 0 ]; then
            icon="[ERROR]"
        elif [ "${pending:-0}" -gt 0 ] || [ "${offline_unc:-0}" -gt 0 ]; then
            icon="[WARN]"
        fi
        
        echo ""
        echo "$icon $dev ($type)"
        echo "    Status: $status | Temp: $temp"
        
        # Mostrar contadores problemáticos
        [ "${realloc:-0}" -gt 0 ] && echo "    [WARN] Setores realocados: $realloc"
        [ "${pending:-0}" -gt 0 ] && echo "    [WARN] Setores pendentes: $pending"
        [ "${offline_unc:-0}" -gt 0 ] && echo "    [WARN] Erros offline: $offline_unc"
        [ -n "$alerts" ] && echo "    Alertas: $alerts"
        
    done < <(grep "^\[SMART\]" "$smart_log")
    
    echo ""
    if [ "$SMART_ERROR_COUNT" -gt 0 ]; then
        echo "[ERROR] $SMART_ERROR_COUNT disco(s) com ERRO - ação necessária!"
    elif [ "$SMART_WARN_COUNT" -gt 0 ]; then
        echo "[INFO] $SMART_WARN_COUNT disco(s) com alertas (monitorar)"
    else
        echo "[OK] Todos os discos saudáveis"
    fi
}
