# 📋 **ANÁLISIS DETALLADO: `99-backup-usb.rules`**

### 🎯 **Propósito del Archivo**

Este archivo contiene **reglas udev** que le dicen al sistema Linux cómo reaccionar automáticamente cuando se conectan o desconectan dispositivos USB de almacenamiento. Es el **cerebro de la detección automática** de tu sistema de respaldo.

---

## 🔍 **¿Qué es udev?**

**udev** es el subsistema de Linux que:
- **Detecta** cuando se conectan/desconectan dispositivos
- **Crea** archivos de dispositivo en `/dev/`
- **Ejecuta** acciones automáticas basadas en reglas
- **Gestiona** permisos y nombres de dispositivos

Piénsalo como el "mayordomo" que vigila la puerta USB y ejecuta tareas cuando llegan "invitados" (dispositivos).

---

## 📖 **Análisis Línea por Línea**

### **Línea 1-2: Comentarios de Documentación**
```plaintext
# Reglas udev para detección automática de dispositivos USB de respaldo
# Este archivo debe ubicarse en /etc/udev/rules.d/99-backup-usb.rules
```
**Función:** Documentación para administradores futuros.

---

### **Línea 4-5: Regla de Detección (ADD)**
```plaintext
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler %k"
```

#### **Desglose de Condiciones:**

| **Condición** | **Significado** | **Ejemplo** |
|---------------|-----------------|-------------|
| `SUBSYSTEM=="block"` | Solo dispositivos de bloque (almacenamiento) | Discos, USBs, no teclados |
| `KERNEL=="sd[a-z][0-9]"` | Nombre del kernel tipo sdXN | `sdb1`, `sdc2`, `sda1` |
| `ENV{ID_BUS}=="usb"` | Conectado por bus USB | No SATA interno, no CD-ROM |
| `ENV{ID_FS_TYPE}!=""` | Tiene sistema de archivos | FAT32, NTFS, ext4, etc. |
| `ACTION=="add"` | Acción de conexión | Se conectó el dispositivo |
| `RUN+="/usr/local/bin/backup-usb-handler %k"` | Ejecutar script handler | Pasa nombre del dispositivo |

#### **¿Qué significa `%k`?**
`%k` es una **variable especial de udev** que contiene el nombre del kernel del dispositivo.

**Ejemplos:**
- Si conectas USB y se asigna como `sdb1` → `%k` = `"sdb1"`
- Si es la segunda partición `sdc2` → `%k` = `"sdc2"`

---

### **Línea 6-7: Regla de Limpieza (REMOVE)**
```plaintext
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ACTION=="remove", RUN+="/usr/local/bin/backup-usb-cleanup %k"
```

#### **Diferencias con la regla ADD:**
- `ACTION=="remove"` → Se ejecuta al **desconectar**
- `ENV{ID_FS_TYPE}!=""` → **Ausente** porque el dispositivo ya no está montado
- `RUN+="/usr/local/bin/backup-usb-cleanup %k"` → Ejecuta script de **limpieza**

---

## ⚙️ **¿Cómo Funciona en la Práctica?**

### **Escenario: Conectar USB**

1. **Usuario conecta USB** 🔌
2. **Kernel detecta dispositivo** → Asigna `/dev/sdb1`
3. **udev procesa reglas** → Lee `99-backup-usb.rules`
4. **Evalúa condiciones:**
   - ✅ `SUBSYSTEM=="block"` (es dispositivo de almacenamiento)
   - ✅ `KERNEL=="sd[a-z][0-9]"` (nombre es `sdb1`)
   - ✅ `ENV{ID_BUS}=="usb"` (conectado por USB)
   - ✅ `ENV{ID_FS_TYPE}!=""` (tiene sistema de archivos FAT32)
   - ✅ `ACTION=="add"` (acción es conexión)
5. **Ejecuta comando:** `/usr/local/bin/backup-usb-handler sdb1`

### **Escenario: Desconectar USB**

1. **Usuario desconecta USB** 🔌❌
2. **Kernel detecta remoción** → `/dev/sdb1` desaparece
3. **udev procesa reglas** → Encuentra regla REMOVE
4. **Ejecuta limpieza:** `/usr/local/bin/backup-usb-cleanup sdb1`

---

## 📁 **¿Por qué `99-backup-usb.rules`?**

### **Numeración en udev:**
- **00-10**: Reglas del sistema base
- **50-70**: Reglas estándar del sistema
- **80-90**: Reglas de aplicaciones
- **99**: **Alta prioridad**, se ejecutan al final

### **¿Por qué al final?**
- Otras reglas ya **montaron** el dispositivo
- Ya se **asignaron permisos**
- El dispositivo está **listo para usar**

---

## 🔧 **Instalación y Ubicación**

### **Donde va el archivo:**
```bash
/etc/udev/rules.d/99-backup-usb.rules
```

### **Permisos requeridos:**
```bash
sudo cp 99-backup-usb.rules /etc/udev/rules.d/
sudo chmod 644 /etc/udev/rules.d/99-backup-usb.rules
sudo udevadm control --reload-rules
```

### **¿Por qué recargar reglas?**
udev lee las reglas **al iniciar**. Para que tome los cambios sin reiniciar:
```bash
sudo udevadm control --reload-rules
```

---

## 🧪 **Testing y Debugging**

### **Ver eventos udev en tiempo real:**
```bash
sudo udevadm monitor --kernel --subsystem-match=block
```

**Output esperado al conectar USB:**
```
KERNEL[1234567.890] add      /devices/.../sdb1 (block)
```

### **Probar regla manualmente:**
```bash
# Ver propiedades del dispositivo
sudo udevadm info --attribute-walk --name=/dev/sdb1

# Simular evento
sudo udevadm trigger --action=add --name=/dev/sdb1
```

### **Ver logs de ejecución:**
```bash
# Logs del sistema
journalctl -f

# Logs específicos del handler
tail -f /var/log/backup-system/usb-events.log
```

---

## ⚠️ **Limitaciones y Consideraciones**

### **¿Qué NO detecta esta regla?**

1. **CD/DVD-ROM**: No son `SUBSYSTEM=="block"` tipo `sd*`
2. **Dispositivos internos**: `ENV{ID_BUS}!="usb"`
3. **USBs sin formato**: `ENV{ID_FS_TYPE}==""`
4. **Dispositivos de red USB**: Son `SUBSYSTEM=="net"`
5. **Teclados/ratones USB**: Son `SUBSYSTEM=="input"`

### **Casos edge:**

1. **USB con múltiples particiones:**
   - `sdb1`, `sdb2`, `sdb3` → Cada una dispara la regla
   - El handler debe manejar esto

2. **Reconexión rápida:**
   - Desconectar y reconectar rápido puede causar condiciones de carrera
   - Lock files previenen esto

3. **Permisos de montaje:**
   - El dispositivo puede detectarse pero no estar montado aún
   - Handler tiene retry logic para esto

---

## 🔗 **Integración con el Sistema**

### **Flujo completo:**
```
USB Conectado
    ↓
udev detecta → 99-backup-usb.rules
    ↓
backup-usb-handler.sh
    ↓
principal.sh --process-usb
    ↓
Proceso de respaldo
    ↓
Notificación Telegram
```

### **Archivos relacionados:**
- `/usr/local/bin/backup-usb-handler` → Script que ejecuta la regla ADD
- `/usr/local/bin/backup-usb-cleanup` → Script que ejecuta la regla REMOVE
- `/var/log/backup-system/usb-events.log` → Log de eventos USB

---

## 💡 **Personalización Avanzada**

### **Detectar solo ciertos fabricantes:**
```plaintext
# Solo USBs de SanDisk
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_VENDOR}=="SanDisk", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler %k"
```

### **Detectar por tamaño mínimo:**
```plaintext
# Solo USBs mayores a 1GB
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", ATTR{size}>"2097152", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler %k"
```

### **Diferentes handlers por sistema de archivos:**
```plaintext
# Para FAT32
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="vfat", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler-fat32 %k"

# Para NTFS
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="ntfs", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler-ntfs %k"
```

---

## 📋 **Resumen Ejecutivo**

### **¿Qué hace este archivo?**
Es la "**puerta de entrada inteligente**" que detecta automáticamente cuando conectas un USB de respaldo y ejecuta el proceso correspondiente.

### **¿Por qué es importante?**
Sin este archivo, tendrías que ejecutar manualmente el comando de respaldo cada vez. Con él, el sistema es **verdaderamente automático**.

### **¿Cómo mejora la seguridad?**
- Solo responde a dispositivos USB específicos
- No interfiere con otros dispositivos del sistema
- Ejecuta scripts controlados en ubicaciones seguras

Este archivo es el **corazón de la automatización** de tu sistema de respaldo, convirtiendo un proceso manual en uno completamente transparente para el usuario. 🚀
