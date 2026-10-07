# Sistema de Respaldo Automático con Autenticación

### 📋 Descripción
Sistema completo de respaldo automático para servidores mediante dispositivos USB, con autenticación mediante firmas digitales, notificaciones vía Telegram y cifrado de archivos de respaldo.

### 🚀 Características
- ✅ **Respaldo automático** al conectar dispositivo USB
- ✅ **Autenticación con firmas digitales** RSA-2048
- ✅ **Notificaciones en tiempo real** vía Telegram
- ✅ **Cifrado de respaldos** con AES-256-CBC
- ✅ **Compresión automática** con gzip
- ✅ **Servicio systemd** para ejecución continua
- ✅ **Logs detallados** de auditoría

### 📁 Estructura del Proyecto
```
Auto_Backup_Linux/
├── README.md                 # Documentación
├── install.sh                # Instalador automático
├── main.sh                   # Script principal del sistema
├── gen_keys.sh               # Generador de llaves RSA
├── setup_telegram.sh         # Configurador de Telegram
├── backup-system.service     # Servicio systemd
├── backup_config.conf        # Configuración para USB
└── messages.sh               # Script de mensajes del sistema
```

### 🔧 Instalación

#### 1. Clonar o descargar el proyecto
```bash
git clone <repositorio>
cd Auto_Backup_Linux
chmod +x ./install.sh
```

#### 2. Ejecutar instalación automática
```bash
sudo ./install.sh --install
```

#### 3. Configurar Telegram
```bash
sudo backup-telegram --setup
```

#### 4. Generar llaves para sysadmins
```bash
sudo backup-genkeys "nombre_admin" ./keys/
```

#### 5. Autorizar la llave pública del sysadmin
```bash
sudo backup-system --add-key ./keys/"nombre_admin"_public.pem
```

#### 6. Establecer contraseña del servidor
```bash
sudo backup-system --set-password
```

#### 7. Habilitar el servicio
```bash
sudo systemctl enable backup-system.service
```

#### 8. Iniciar el servicio
```bash
sudo systemctl start backup-system.service
```

### 📱 Configuración de Telegram

#### Crear Bot
1. Contactar a @BotFather en Telegram
2. Usar comando `/newbot`
3. Seguir instrucciones y obtener token

#### Obtener Chat ID
1. Enviar mensaje al bot
2. Visitar: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Buscar `"chat":{"id":XXXXXXXXX}`

### 🔐 Preparación de USB

#### Estructura requerida en USB:
```
USB/
├── backup_config.conf   # Configuración de respaldo
├── <sysadmin_id>_private.pem # Llave privada del sysadmin
└── sysadmin_id.txt      # ID del sysadmin
```

La llave pública correspondiente debe autorizarse en el servidor con
`sudo backup-system --add-key <sysadmin_id>_public.pem`.

#### Ejemplo de backup_config.conf:
```properties
BACKUP_DIRS="/etc /home"
BACKUP_NAME="primary_server"
EXCLUDE_PATTERNS="*.tmp *.log.*"
SYSADMIN_NAME="Administrator"
BACKUP_DESCRIPTION="Automatic backup of critical directories"
```

### 🎮 Uso del Sistema

#### Comandos principales:
```bash
# Ver estado del sistema
sudo backup-system --status

# Ver el tiempo real la ejecución
sudo backup-system --monitor

# Agregar llave pública autorizada
sudo backup-system --add-key /path/public.pem
```

#### Proceso automático:
1. Conectar USB con archivos requeridos
2. Sistema detecta automáticamente el dispositivo
3. Verifica autenticación por firma digital
4. Solicita contraseña vía Telegram
5. Valida contraseña del servidor
6. Crea respaldos cifrados y comprimidos
7. Notifica finalización vía Telegram

### 🔍 Pruebas

#### Verificar instalación:
```bash
sudo backup-system --status
systemctl status backup-system.service
```
### 📂 Ubicación de Archivos

#### Configuración:
- `/etc/backup-system/server.conf` - Configuración del servidor
- `/etc/backup-system/authorized_keys` - Llaves públicas autorizadas
- `/etc/backup-system/server_hash` - Hash de contraseña del servidor
- `/etc/backup-system/telegram.conf` - Configuración de Telegram

#### Temporales:
- `/tmp/backup-system/` - Archivos temporales

### 🛡️ Seguridad

#### Autenticación multinivel:
1. **Firma digital**: Verificación con llaves RSA-2048
2. **Contraseña del servidor**: Hash SHA-256 almacenado
3. **Autorización de llaves**: Lista de llaves públicas autorizadas

#### Cifrado:
- **Respaldos**: AES-256-CBC con contraseña del servidor
- **Comunicación**: HTTPS para API de Telegram

Los nuevos respaldos usan la extensión `.tar.gz.enc`: primero se comprimen con gzip y
después se cifran con OpenSSL. Para restaurar uno:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -in primary_server_etc_YYYYMMDD_HHMMSS.tar.gz.enc \
  -out backup.tar.gz
tar -xzf backup.tar.gz -C /ruta/de/restauracion
```

Los respaldos creados por versiones anteriores deben descifrarse con el formato
histórico (sin `-pbkdf2`) antes de extraerlos.

### 🔧 Solución de Problemas

#### Ver logs detallados:
```bash
journalctl -u backup-system.service -f
```

#### Verificar detección USB:
```bash
udevadm monitor --kernel --subsystem-match=block
```

#### Probar notificaciones Telegram:
```bash
sudo backup-telegram --test
```

### 📋 Requisitos del Sistema
- **OS**: Debian/Ubuntu Linux
- **Privilegios**: root
- **Dependencias**: openssl, curl, jq, tar, gzip, udev, systemd, util-linux, coreutils

`BACKUP_MAX_SIZE` limita el tamaño de cada respaldo (por ejemplo, `1G`, `500M`
o `1024K`). El sistema comprueba el espacio libre del USB y elimina cualquier
archivo parcial que supere el límite. Solo se permite un respaldo activo; los
eventos USB concurrentes se ignoran y quedan registrados. `LOG_RETENTION_DAYS`
controla la limpieza de archivos de log rotados, no de respaldos válidos.
- **Red**: Acceso a internet para Telegram

### 👥 Autor
**Emmanuel Alexis Esperilla Castro** 

### 📄 Licencia
Este proyecto está bajo la Licencia MIT. Siéntete libre de usarlo para aprendizaje y proyectos personales.

---
*Fecha: 6 de octubre de 2026*
