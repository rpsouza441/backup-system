# Sistema de Backup Modular

Sistema de backup automatizado com relatórios por email, em arquitetura modular com mounts OneDrive persistentes.

## Funcionalidades

- **Backup rsync incremental** com versionamento diário
- **Backup TAR comprimido** para OneDrive
- **Verificação SMART** dos discos
- **Relatórios por email** com status detalhado
- **Mounts OneDrive persistentes** via systemd + rclone
- **Gestão automática** de containers Docker durante backup

## Estrutura

```
/opt/backup-system/
├── backup-orchestrator.sh     # Orquestrador de backup
├── report-generator.sh        # Gerador de relatórios
├── config/
│   ├── backup.conf            # Config do backup (criar a partir do .example)
│   ├── backup.conf.example    # Exemplo de configuração
│   ├── report.conf            # Config do relatório (criar a partir do .example)
│   ├── report.conf.example    # Exemplo de configuração
│   └── msmtprc.example        # Exemplo config SMTP
├── lib/common.sh              # Funções compartilhadas
├── services/
│   ├── storage-mounts.sh      # Montagem de storages físicos
│   ├── docker-control.sh      # Controle de containers Docker
│   ├── smart-check.sh         # Verificação SMART dos discos
│   ├── rsync-backup.sh        # Backup rsync incremental
│   ├── tar-backup.sh          # Criação de TAR para OneDrive
│   ├── cleanup.sh             # Limpeza de backups antigos
│   └── report/                # Módulos do relatório
│       ├── analyze-backup.sh
│       ├── analyze-smart.sh
│       ├── analyze-rsync.sh
│       ├── analyze-disk.sh
│       └── send-email.sh
└── systemd/
    ├── backup.service
    ├── backup-report.service
    ├── backup-report.timer    # Agenda relatório às 09:00
    └── rclone-*.service       # Mounts OneDrive
```

## Configuração Inicial

### 1. Copiar arquivos para o servidor

```bash
sudo cp -r * /opt/backup-system/
sudo chmod +x /opt/backup-system/*.sh
sudo chmod +x /opt/backup-system/services/*.sh
sudo chmod +x /opt/backup-system/services/report/*.sh
```

### 2. Configurar arquivos de configuração

Os arquivos de configuração devem ser criados a partir dos exemplos:

```bash
cd /opt/backup-system/config

# Criar configuração de backup
cp backup.conf.example backup.conf

# Criar configuração de relatório
cp report.conf.example report.conf

# Editar com seus valores
nano backup.conf
nano report.conf
```

### 3. Configurações Obrigatórias

#### Arquivo: `config/backup.conf`

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `DATA_SOURCE` | Diretório fonte dos dados | `/path/to/source` |
| `DATA_DEST` | Diretório destino do backup | `/path/to/backup` |
| `STORAGES` | Array de discos para montar | Ver formato abaixo |
| `ONEDRIVE_MOUNTS` | Array de mounts OneDrive | Ver formato abaixo |

**Formato STORAGES** (obter UUID com `sudo blkid`):
```bash
"UUID:MOUNT_POINT:LABEL:CRITICAL"
# Exemplo:
"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:/storageX:storageX:1"
```

**Formato ONEDRIVE_MOUNTS**:
```bash
"REMOTE_PATH:LOCAL_PATH:MODE"
# Exemplo:
"SERVER-BACKUP:/SERVER-BACKUP:writes"
```

#### Arquivo: `config/report.conf`

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `EMAIL` | Email para receber relatórios | `admin@exemplo.com` |
| `WEBHOOK_URL` | URL de webhook (opcional) | `https://hooks.slack.com/...` |
| `SMART_ALERT_LEVEL` | Nível de alerta SMART | `INFO`, `WARNING`, `CRITICAL` |

### 4. Configurar envio de email (msmtp)

```bash
# Instalar msmtp
sudo apt install msmtp msmtp-mta

# Copiar configuração exemplo
sudo cp /opt/backup-system/config/msmtprc.example /etc/msmtprc
sudo chmod 600 /etc/msmtprc

# Editar com suas credenciais
sudo nano /etc/msmtprc
```

**Para criar uma App Password do Gmail:**
1. Acesse: https://myaccount.google.com/apppasswords
2. Em "Selecionar app", escolha "Mail"
3. Em "Selecionar dispositivo", escolha "Outro" e digite o nome do servidor
4. Copie a senha de 16 caracteres gerada (sem espaços)
5. Cole no campo `password` do arquivo `/etc/msmtprc`

**Testar envio:**
```bash
echo "Teste de email" | msmtp seu_email@gmail.com
```

### 5. Configurar rclone (OneDrive)

```bash
# Configurar rclone
rclone config

# Seguir o wizard para configurar o remote "onedrive"
# O nome do remote deve ser "onedrive"
```

### 6. Instalar services do systemd

```bash
sudo cp /opt/backup-system/systemd/*.service /etc/systemd/system/
sudo cp /opt/backup-system/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload

# OneDrive persistente
sudo systemctl enable --now rclone-onedrive@SERVER-BACKUP.service

# Backup no boot
sudo systemctl enable backup.service

# Relatório diário às 09:00
sudo systemctl enable --now backup-report.timer
```

## Uso

### Executar backup manualmente
```bash
sudo /opt/backup-system/backup-orchestrator.sh
```

### Gerar relatório manualmente
```bash
sudo /opt/backup-system/report-generator.sh
```

### Verificar status dos serviços
```bash
# Status do timer de relatório
systemctl status backup-report.timer

# Status dos mounts OneDrive
systemctl status rclone-onedrive@SERVER-BACKUP.service

# Últimos logs de backup
journalctl -u backup.service -n 50
```

## Logs

| Localização | Descrição |
|-------------|-----------|
| `/var/log/backup-system/backup_*.log` | Logs de execução do backup |
| `/var/log/backup-system/rsync_*.log` | Logs detalhados do rsync |
| `/var/log/backup-system/smart_latest.log` | Último relatório SMART |
| `/var/log/backup-system/reports/` | Relatórios gerados |
| `/var/log/backup-system/rclone-*.log` | Logs do rclone |

## Troubleshooting

### Backup não executa
```bash
# Verificar se há lock ativo
cat /var/run/backup.lock
# Se o processo não existir, remover o lock
sudo rm /var/run/backup.lock
```

### OneDrive não monta
```bash
# Verificar logs do rclone
journalctl -u rclone-onedrive@SERVER-BACKUP.service -n 50

# Testar manualmente
rclone lsd onedrive:SERVER-BACKUP
```

### Email não envia
```bash
# Testar msmtp
echo "Teste" | msmtp -v seu_email@gmail.com

# Verificar log
cat /var/log/msmtp.log
```
