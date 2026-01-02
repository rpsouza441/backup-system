#!/bin/bash
# =============================================================================
# smart-check.sh - Gera relatório SMART dos discos
# =============================================================================

set -e

# Carregar biblioteca comum
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# MAIN
# =============================================================================

SMART_LOG="$LOG_DIR/smart_$(date +%Y%m%d_%H%M%S).log"

log "Gerando relatório SMART..."

if ! command -v smartctl >/dev/null 2>&1; then
    log_warn "smartctl não instalado; pulando coleta SMART."
    exit 0
fi

# Cabeçalho
{
    echo "======== SMART REPORT ========"
    date '+%F %T'
} > "$SMART_LOG"

dev_count=0
warn_count=0

# Lista dispositivos e tipos corretos (sat/scsi/nvme)
while read -r DEV TYPE; do
    [ -z "$DEV" ] && continue
    dev_count=$((dev_count+1))
    OPT=""
    [ -n "$TYPE" ] && OPT="-d $TYPE"

    # Health
    H_OUT="$(smartctl -H $OPT "$DEV" 2>&1)"
    OVERALL="$(printf '%s\n' "$H_OUT" | awk -F: '/overall-health|Health Status/ {gsub(/[ \t]/,"",$2); print $2; exit}')"
    [ -z "$OVERALL" ] && OVERALL="UNKNOWN"

    NOTE=""
    printf '%s\n' "$H_OUT" | grep -q "Incomplete response" && NOTE="${NOTE} incomplete_response"
    printf '%s\n' "$H_OUT" | grep -qi "marginal Attributes" && NOTE="${NOTE} marginal_attributes"

    if [ "$TYPE" = "nvme" ]; then
        A_OUT="$(smartctl -x $OPT "$DEV" 2>&1)"
        TEMP="$(printf '%s\n' "$A_OUT" | awk -F: '/[Cc]omposite [Tt]emperature|[Tt]emperature/ {gsub(/[^0-9]/,"",$2); if($2!=""){print $2; exit}}')"
        [ -z "$TEMP" ] && TEMP="NA"
        CRIT="$(printf '%s\n' "$A_OUT" | awk -F: '/Critical Warning/ {gsub(/[ \t]/,"",$2); print $2; exit}')"
        MDI="$(printf '%s\n' "$A_OUT" | awk -F: '/Media and Data Integrity Errors/ {gsub(/[ \t]/,"",$2); print $2; exit}')"
        EIL="$(printf '%s\n' "$A_OUT" | awk -F: '/Error Information Log Entries/ {gsub(/[ \t]/,"",$2); print $2; exit}')"

        ALERTS=""
        [ -n "$CRIT" ] && [ "$CRIT" != "0x00" ] && ALERTS="$ALERTS crit=$CRIT"
        [ -n "$MDI" ]  && [ "$MDI"  != "0"    ] && ALERTS="$ALERTS mdi=$MDI"
        [ -n "$EIL" ]  && [ "$EIL"  != "0"    ] && ALERTS="$ALERTS eil=$EIL"
        [ "$TEMP" != "NA" ] && [ "$TEMP" -ge 55 ] && ALERTS="$ALERTS hot=${TEMP}C"

        printf '[SMART] dev=%s type=nvme status=%s temp=%sC%s%s\n' \
            "$DEV" "$OVERALL" "$TEMP" \
            "${ALERTS:+ alerts=[$ALERTS]}" \
            "${NOTE:+ note=[$NOTE]}" >> "$SMART_LOG"

        { [ "$OVERALL" != "PASSED" ] || [ -n "$ALERTS$NOTE" ]; } && warn_count=$((warn_count+1))
    else
        A_OUT="$(smartctl -A $OPT "$DEV" 2>&1)"
        # Extração clássica SATA/SAS
        REALLOC="$(printf '%s\n' "$A_OUT" | awk '$2=="Reallocated_Sector_Ct"{print $10}')"
        PENDING="$(printf '%s\n' "$A_OUT" | awk '$2=="Current_Pending_Sector"{print $10}')"
        OFFUNC="$(printf '%s\n' "$A_OUT" | awk '$2=="Offline_Uncorrectable"{print $10}')"
        RUNCOR="$(printf '%s\n' "$A_OUT" | awk '$2=="Reported_Uncorrectable_Errors"{print $10}')"
        CTIMEO="$(printf '%s\n' "$A_OUT" | awk '$2=="Command_Timeout"{print $10}')"
        TEMP="$(printf '%s\n' "$A_OUT" | awk '$2=="Temperature_Celsius"{print $10} $2=="Airflow_Temperature_Cel"{print $10}' | head -n1)"
        [ -z "$TEMP" ] && TEMP="NA"

        ALERTS=""
        for v in REALLOC PENDING OFFUNC RUNCOR CTIMEO; do
            val=${!v}
            [ -n "$val" ] && [ "$val" -gt 0 ] && ALERTS="$ALERTS $(echo "$v" | tr '[:upper:]_' '[:lower:]-')=$val"
        done
        [ "$TEMP" != "NA" ] && [ "$TEMP" -ge 55 ] && ALERTS="$ALERTS hot=${TEMP}C"

        printf '[SMART] dev=%s type=%s status=%s temp=%sC realloc=%s pending=%s offline_unc=%s reported_unc=%s timeout=%s%s%s\n' \
            "$DEV" "$TYPE" "$OVERALL" "${TEMP}" \
            "${REALLOC:-0}" "${PENDING:-0}" "${OFFUNC:-0}" "${RUNCOR:-0}" "${CTIMEO:-0}" \
            "${ALERTS:+ alerts=[$ALERTS]}" \
            "${NOTE:+ note=[$NOTE]}" >> "$SMART_LOG"

        { [ "$OVERALL" != "PASSED" ] || [ -n "$ALERTS$NOTE" ]; } && warn_count=$((warn_count+1))
    fi
done < <(smartctl --scan | awk '{print $1,$3}')

# Criar link simbólico para o último relatório
ln -sf "$SMART_LOG" "$LOG_DIR/smart_latest.log"

log "SMART: $dev_count dispositivo(s) analisado(s), alertas=$warn_count | arquivo: $SMART_LOG"

exit 0
