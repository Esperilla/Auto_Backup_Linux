# Automatic Backup System with Authentication

### 📋 Description
Complete automatic backup system for servers using USB devices, with digital signature authentication, Telegram notifications, and backup file encryption.

### 🚀 Features
- ✅ **Automatic backup** when a USB device is connected
- ✅ **Digital signature authentication** with RSA-2048
- ✅ **Real-time notifications** via Telegram
- ✅ **Backup encryption** with AES-256-CBC
- ✅ **Automatic compression** with gzip
- ✅ **systemd service** for continuous execution
- ✅ **Detailed audit logs**

### 📁 Project Structure
```
Auto_Backup_Linux/
├── README.md                 # Documentation
├── install.sh                # Automatic installer
├── main.sh                   # Main system script
├── gen_keys.sh               # RSA key generator
├── setup_telegram.sh         # Telegram configurator
├── backup-system.service     # systemd service
├── backup_config.conf        # USB configuration
└── messages.sh               # System messaging script
```

### 🔧 Installation

#### 1. Clone or download the project
```bash
git clone <repository>
cd Auto_Backup_Linux
chmod +x ./install.sh
```

#### 2. Run the automatic installation
```bash
sudo ./install.sh --install
```

#### 3. Configure Telegram
```bash
sudo backup-telegram --setup
```

#### 4. Generate keys for sysadmins
```bash
sudo backup-genkeys "admin_name" ./keys/
```

#### 5. Authorize the sysadmin's public key
```bash
sudo backup-system --add-key ./keys/"admin_name"_public.pem
```

#### 6. Set the server password
```bash
sudo backup-system --set-password
```

#### 7. Enable the service
```bash
sudo systemctl enable backup-system.service
```

#### 8. Start the service
```bash
sudo systemctl start backup-system.service
```

### 📱 Telegram Configuration

#### Create a Bot
1. Contact @BotFather on Telegram
2. Use the `/newbot` command
3. Follow the instructions and obtain the token

#### Get the Chat ID
1. Send a message to the bot
2. Visit: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Look for `"chat":{"id":XXXXXXXXX}`

### 🔐 USB Preparation

#### Required USB structure:
```
USB/
├── backup_config.conf   # Backup configuration
├── <sysadmin_id>_private.pem # Sysadmin private key
└── sysadmin_id.txt      # Sysadmin ID
```

The corresponding public key must be authorized on the server with
`sudo backup-system --add-key <sysadmin_id>_public.pem`.

#### Example backup_config.conf:
```properties
BACKUP_DIRS="/etc /home"
BACKUP_NAME="primary_server"
EXCLUDE_PATTERNS="*.tmp *.log.*"
SYSADMIN_NAME="Administrator"
BACKUP_DESCRIPTION="Backup of critical directories"
```

### 🎮 System Usage

#### Main commands:
```bash
# View system status
sudo backup-system --status

# Monitor execution in real time
sudo backup-system --monitor

# Add an authorized public key
sudo backup-system --add-key /path/public.pem
```

#### Automatic process:
1. Connect a USB device containing the required files
2. The system automatically detects the device
3. It verifies authentication using the digital signature
4. It requests the password via Telegram
5. It validates the server password
6. It creates encrypted and compressed backups
7. It notifies you of completion via Telegram

### 🔍 Testing

#### Verify the installation:
```bash
sudo backup-system --status
systemctl status backup-system.service
```
### 📂 File Locations

#### Configuration:
- `/etc/backup-system/server.conf` - Server configuration
- `/etc/backup-system/authorized_keys` - Authorized public keys
- `/etc/backup-system/server_hash` - Server password hash
- `/etc/backup-system/telegram.conf` - Telegram configuration

#### Temporary files:
- `/tmp/backup-system/` - Temporary files

### 🛡️ Security

#### Multi-level authentication:
1. **Digital signature**: Verification using RSA-2048 keys
2. **Server password**: Stored SHA-256 hash
3. **Key authorization**: List of authorized public keys

#### Encryption:
- **Backups**: AES-256-CBC with the server password
- **Communication**: HTTPS for the Telegram API

New backups use the `.tar.gz.enc` extension: they are compressed with gzip and
then encrypted with OpenSSL. To restore one:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -in primary_server_etc_YYYYMMDD_HHMMSS.tar.gz.enc \
  -out backup.tar.gz
tar -xzf backup.tar.gz -C /restore/path
```

Backups created by earlier versions must be decrypted with the historical
format (without `-pbkdf2`) before extraction.

### 🔧 Troubleshooting

#### View detailed logs:
```bash
journalctl -u backup-system.service -f
```

#### Verify USB detection:
```bash
udevadm monitor --kernel --subsystem-match=block
```

#### Test Telegram notifications:
```bash
sudo backup-telegram --test
```

### 📋 System Requirements
- **OS**: Debian/Ubuntu Linux
- **Privileges**: root
- **Dependencies**: openssl, curl, jq, tar, gzip, udev, systemd, util-linux, coreutils

`BACKUP_MAX_SIZE` limits each backup size (for example, `1G`, `500M`, or
`1024K`). The system checks free USB space and removes any partial file that
exceeds the limit. Only one backup may run at a time; concurrent USB events are
ignored and logged. `LOG_RETENTION_DAYS` controls cleanup of rotated log files,
not valid backups.
- **Network**: Internet access for Telegram

### 👥 Author
**Emmanuel Alexis Esperilla Castro** 

### 📄 License
This project is licensed under the MIT License. Feel free to use it for learning and personal projects.

---
*Date: October 6, 2026*
