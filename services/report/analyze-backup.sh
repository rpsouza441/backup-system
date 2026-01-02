#!/bin/bash
# =============================================================================
# analyze-backup.sh - Analisa log principal do backup
# Retorna: STATUS, info de storages, docker, TAR
# =============================================================================

# Variáveis de saída (para serem capturadas pelo orquestrador)
BACKUP_STATUS="UNKNOWN"
BACKUP_DURATION=""
STORAGE_STATUS=""
DOCKER_STATUS=""
TAR_STATUS=""
ONEDRIVE_STATUS=""

analyze_backup() {
    local backup_log="$1"
    
    if [ ! -f "$backup_log" ]; then
        echo "ERRO: Log não encontrado: $backup_log"
        BACKUP_STATUS="MISSING"
        return 1
    fi
    
    # Status geral
    if grep -q "STATUS: SUCESSO" "$backup_log"; then
        BACKUP_STATUS="SUCCESS"
    elif grep -q "STATUS: AVISO/ERRO" "$backup_log"; then
        BACKUP_STATUS="WARNING"
    else
        BACKUP_STATUS="UNKNOWN"
    fi
    
    # Duração
    local inicio fim
    inicio=$(grep "Iniciando" "$backup_log" | head -1 | grep -oP '\[\K[^\]]+')
    fim=$(grep "Script finalizado" "$backup_log" | tail -1 | grep -oP '\[\K[^\]]+')
    if [ -n "$inicio" ] && [ -n "$fim" ]; then
        local inicio_ts fim_ts duracao
        inicio_ts=$(date -d "$inicio" +%s 2>/dev/null)
        fim_ts=$(date -d "$fim" +%s 2>/dev/null)
        if [ -n "$inicio_ts" ] && [ -n "$fim_ts" ]; then
            duracao=$((fim_ts - inicio_ts))
            BACKUP_DURATION="$((duracao/60))m $((duracao%60))s"
        fi
    fi
    
    # Storages
    local mounted=0 total=4
    if grep -q "\[MOUNTCHK\] storage0 OK" "$backup_log"; then mounted=$((mounted+1)); fi
    if grep -q "\[MOUNTCHK\] storage1 OK" "$backup_log"; then mounted=$((mounted+1)); fi
    if grep -q "\[MOUNTCHK\] storage2 OK" "$backup_log"; then mounted=$((mounted+1)); fi
    if grep -q "\[MOUNTCHK\] storage3 OK" "$backup_log"; then mounted=$((mounted+1)); fi
    STORAGE_STATUS="${mounted}/${total}"
    
    # Docker
    if grep -q "Containers parados com sucesso" "$backup_log" && grep -q "Containers reiniciados com sucesso" "$backup_log"; then
        DOCKER_STATUS="OK"
    else
        DOCKER_STATUS="WARN"
    fi
    
    # TAR - ATUALIZADO para novos padrões do backup-system
    if grep -q "TAR validado: integridade OK" "$backup_log" && grep -q "Verificação OK: tamanhos correspondentes" "$backup_log"; then
        local tar_size
        # Usar awk para pegar o valor após "Tamanho do TAR:" independente de colunas
        tar_size=$(grep "Tamanho do TAR:" "$backup_log" | tail -1 | awk -F'Tamanho do TAR: ' '{print $2}' | xargs)
        TAR_STATUS="OK (${tar_size:-?})"
    elif grep -q "SUCESSO: TAR criado" "$backup_log"; then
        TAR_STATUS="OK"
    elif grep -q "TAR corrompido" "$backup_log"; then
        TAR_STATUS="ERRO (corrompido)"
    elif grep -q "Falha definitiva ao copiar TAR" "$backup_log"; then
        TAR_STATUS="ERRO (cópia falhou)"
    elif grep -q "Pulando TAR\|pulando TAR" "$backup_log"; then
        TAR_STATUS="SKIP"
    else
        TAR_STATUS="N/A"
    fi
    
    # Cloud Verification
    CLOUD_VERIFY=""
    if grep -q "Verificação OK: tamanhos correspondentes" "$backup_log"; then
        CLOUD_VERIFY="OK"
    fi
    
    # OneDrive
    local od_ok=0 od_total=3
    if grep -q "\[MOUNTCHK\] SERVER-BACKUP OK" "$backup_log"; then od_ok=$((od_ok+1)); fi
    if grep -q "\[MOUNTCHK\] JPG OK" "$backup_log"; then od_ok=$((od_ok+1)); fi
    if grep -q "\[MOUNTCHK\] IMMICH OK" "$backup_log"; then od_ok=$((od_ok+1)); fi
    ONEDRIVE_STATUS="${od_ok}/${od_total}"
}

# Gerar seção detalhada
generate_backup_details() {
    local backup_log="$1"
    
    echo ""
    echo "ANÁLISE DO BACKUP"
    echo "=================="
    echo "Log: $(basename "$backup_log")"
    echo ""
    
    echo "STATUS GERAL: $BACKUP_STATUS"
    [ -n "$BACKUP_DURATION" ] && echo "Duração: $BACKUP_DURATION"
    echo ""
    
    echo "STORAGES: $STORAGE_STATUS montados"
    for i in 0 1 2 3; do
        if grep -q "\[MOUNTCHK\] storage${i} OK" "$backup_log"; then
            echo "  [OK] Storage${i}"
        else
            echo "  [ERROR] Storage${i}"
        fi
    done
    echo ""
    
    echo "ONEDRIVE: $ONEDRIVE_STATUS acessíveis"
    for name in SERVER-BACKUP JPG IMMICH; do
        if grep -q "\[MOUNTCHK\] $name OK" "$backup_log"; then
            echo "  [OK] $name"
        else
            echo "  [ERROR] $name"
        fi
    done
    echo ""
    
    echo "DOCKER: $DOCKER_STATUS"
    echo "TAR: $TAR_STATUS"
    [ -n "$CLOUD_VERIFY" ] && echo "[OK] Integridade Cloud: Verificação de tamanho correspondente"
}
