# Sistema de Backup Modular

Sistema de backup + relatórios em arquitetura modular com mounts OneDrive persistentes.

## Estrutura

```
/opt/backup-system/
├── backup-orchestrator.sh     # Orquestrador de backup
├── report-generator.sh        # Gerador de relatórios
├── config/
│   ├── backup.conf            # Config do backup
│   ├── report.conf            # Config do relatório/email  
│   └── msmtprc.example        # Exemplo config SMTP
├── lib/common.sh              # Funções compartilhadas
├── services/
│   ├── storage-mounts.sh
│   ├── docker-control.sh
│   ├── smart-check.sh
│   ├── rsync-backup.sh
│   ├── tar-backup.sh
│   ├── cleanup.sh
│   └── report/                # Módulos do relatório
│       ├── analyze-backup.sh
│       ├── analyze-smart.sh
│       ├── analyze-rsync.sh
│       ├── analyze-disk.sh
│       └── send-email.sh
└── systemd/
    ├── backup.service
    ├── backup-report.service
    ├── backup-report.timer    # Agenda 09:00
    └── rclone-*.service       # Mounts OneDrive
```

## Instalação

### 1. Copiar arquivos
```bash
sudo cp -r backup-system/* /opt/backup-system/
sudo chmod +x /opt/backup-system/*.sh
sudo chmod +x /opt/backup-system/services/*.sh
sudo chmod +x /opt/backup-system/services/report/*.sh
```

### 2. Instalar msmtp (para envio de email)
```bash
sudo apt install msmtp msmtp-mta
sudo cp /opt/backup-system/config/msmtprc.example /etc/msmtprc
sudo chmod 600 /etc/msmtprc
# Editar /etc/msmtprc com sua senha real

# Testar
echo "Teste" | msmtp seu_email@gmail.com
```

### 3. Instalar services
```bash
sudo cp /opt/backup-system/systemd/*.service /etc/systemd/system/
sudo cp /opt/backup-system/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload

# OneDrive persistente
sudo systemctl enable --now rclone-onedrive@SERVER-BACKUP.service
sudo systemctl enable --now rclone-onedrive-jpb.service
sudo systemctl enable --now rclone-onedrive-immich.service

# Backup no boot
sudo systemctl enable backup.service

# Relatório às 09:00
sudo systemctl enable --now backup-report.timer
```

### 4. Remover container Docker antigo
```bash
docker stop backup-reporter
docker rm backup-reporter
```

## Uso Manual
```bash
# Executar backup
sudo /opt/backup-system/backup-orchestrator.sh

# Gerar relatório agora
sudo /opt/backup-system/report-generator.sh
```

## Logs
- `/var/log/backup-system/backup_*.log` - Backup
- `/var/log/backup-system/reports/` - Relatórios
