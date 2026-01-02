#!/bin/bash
# =============================================================================
# send-email.sh - Envia relatório por email via msmtp
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/config/report.conf" 2>/dev/null || true

send_email() {
    local subject="$1"
    local body_file="$2"
    local recipient="${EMAIL:-}"
    
    if [ -z "$recipient" ]; then
        echo "ERRO: EMAIL não configurado em report.conf"
        return 1
    fi
    
    if [ ! -f "$body_file" ]; then
        echo "ERRO: Arquivo de corpo não encontrado: $body_file"
        return 1
    fi
    
    # Verificar se msmtp está instalado
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "ERRO: msmtp não instalado. Execute: sudo apt install msmtp msmtp-mta"
        return 1
    fi
    
    # Enviar email
    {
        echo "To: $recipient"
        echo "From: ${SMTP_USER:-backup@localhost}"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        cat "$body_file"
    } | msmtp "$recipient"
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo "Email enviado para: $recipient"
        return 0
    else
        echo "ERRO ao enviar email (código: $result)"
        return 1
    fi
}

# Webhook como fallback
send_webhook() {
    local subject="$1"
    local body_file="$2"
    local webhook_url="${WEBHOOK_URL:-}"
    
    if [ -z "$webhook_url" ]; then
        return 1
    fi
    
    local msg
    msg=$(printf '%s\n\n%s' "$subject" "$(head -30 "$body_file")")
    
    # Escape para JSON
    local body
    body=$(printf '%s' "$msg" | sed -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g')
    local payload
    payload=$(printf '{"text":"%s"}' "$body")
    
    curl -fsS -X POST -H 'Content-Type: application/json' --data "$payload" "$webhook_url"
}
