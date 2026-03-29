# Sistema de Backup Modular

Sistema de backup e relatório em arquitetura modular, com execução orquestrada por `systemd`, cópia principal via `rsync`, arquivamento em `tar.gz` e integração com mounts `rclone`.

## Estrutura

```text
/opt/backup-system/
├── backup-orchestrator.sh
├── report-generator.sh
├── config/
│   ├── backup.conf
│   ├── report.conf
│   └── msmtprc.example
├── lib/
│   └── common.sh
├── services/
│   ├── storage-mounts.sh
│   ├── docker-control.sh
│   ├── smart-check.sh
│   ├── rsync-backup.sh
│   ├── tar-backup.sh
│   ├── cleanup.sh
│   └── report/
│       ├── analyze-backup.sh
│       ├── analyze-smart.sh
│       ├── analyze-rsync.sh
│       ├── analyze-disk.sh
│       └── send-email.sh
└── systemd/
    ├── backup.service
    ├── backup-report.service
    ├── backup-report.timer
    ├── rclone-onedrive@.service
    ├── rclone-onedrive-jpb.service
    └── rclone-onedrive-immich.service
```

## Função de Cada Arquivo

### Scripts principais

- `backup-orchestrator.sh`: coordena toda a rotina de backup. Executa montagem de storages, verificação SMART, checagem dos mounts remotos, parada de containers, `rsync`, criação do TAR, limpeza, reinício do Docker e geração do resumo final.
- `report-generator.sh`: localiza os logs mais recentes, consolida as análises do backup, define o status geral do dia, gera o relatório textual e tenta enviá-lo por email ou webhook.

### Configuração

- `config/backup.conf.example`: modelo de configuração da rotina de backup, incluindo paths, storages, mounts remotos, retenção e timeouts.
- `config/report.conf.example`: modelo de configuração do relatório, com destinatário, webhook, diretórios e retenção.
- `config/msmtprc.example`: exemplo de configuração do `msmtp` para envio de email.

### Biblioteca compartilhada

- `lib/common.sh`: reúne funções comuns de log, lock de execução, montagem por UUID, verificação de espaço, checagem de saúde de mounts `rclone` e utilitários usados pelos demais scripts.

### Serviços de backup

- `services/storage-mounts.sh`: monta e valida os storages físicos definidos em configuração.
- `services/docker-control.sh`: para ou reinicia os containers Docker antes e depois do backup.
- `services/smart-check.sh`: coleta informações SMART dos discos e grava um log resumido para consumo posterior pelo relatório.
- `services/rsync-backup.sh`: executa o espelhamento principal dos dados com `rsync`, incluindo verificações de espaço e estatísticas de execução.
- `services/tar-backup.sh`: cria um arquivo compactado da cópia local, valida sua integridade e tenta copiar o TAR para o destino remoto.
- `services/cleanup.sh`: remove arquivos antigos conforme a política de retenção, incluindo TARs, pastas diárias e logs.

### Módulos de relatório

- `services/report/analyze-backup.sh`: interpreta o log principal do backup e extrai status geral, duração, storages, Docker, TAR e disponibilidade dos mounts remotos.
- `services/report/analyze-smart.sh`: interpreta o log SMART e classifica discos em estados normais, alerta ou erro.
- `services/report/analyze-rsync.sh`: lê o log do `rsync`, identifica erros e resume estatísticas de transferência.
- `services/report/analyze-disk.sh`: avalia ocupação dos storages e resume espaço em disco no relatório final.
- `services/report/send-email.sh`: envia o relatório por `msmtp` e, opcionalmente, por webhook quando configurado.

### Unidades systemd

- `systemd/backup.service`: executa o orquestrador de backup no boot, aguardando dependências críticas como rede, sincronização de horário e mount remoto principal.
- `systemd/backup-report.service`: executa o gerador de relatório como serviço `oneshot`.
- `systemd/backup-report.timer`: agenda a geração diária do relatório.
- `systemd/rclone-onedrive@.service`: unit genérica para mounts `rclone` baseados em instância.
- `systemd/rclone-onedrive-jpb.service`: unit específica para um mount remoto adicional.
- `systemd/rclone-onedrive-immich.service`: unit específica para outro mount remoto adicional.

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
- `/var/log/backup-system/smart_*.log` - Coleta SMART
- `/var/log/backup-system/rsync_*.log` - Execuções do rsync
- `/var/log/backup-system/backup-service.log` - Saída agregada do `backup.service`
- `/var/log/backup-system/report-service.log` - Saída agregada do `backup-report.service`
- `/var/log/backup-system/reports/` - Relatórios
