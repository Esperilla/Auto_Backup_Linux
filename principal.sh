#!/bin/bash

#===============================================================================
# SISTEMA DE RESPALDO AUTOMÁTICO CON AUTENTICACIÓN Y NOTIFICACIONES
# Proyecto Final - Programación en Administración de Servicios
# Autores: Emmanuel Alexis Esperilla Castro y Erick Jair Morales Romero
# Fecha: 19 de junio de 2025
#===============================================================================

# Configuración global
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/backup-system"
TEMP_DIR="/tmp/backup-system"
USB_MOUNT_BASE="/media"

# Archivos de configuración
SERVER_CONFIG="$CONFIG_DIR/server.conf"
SYSADMIN_KEYS="$CONFIG_DIR/authorized_keys"
SERVER_HASH="$CONFIG_DIR/server_hash"
TELEGRAM_CONFIG="$CONFIG_DIR/telegram.conf"

#===============================================================================
# FUNCIONES DE UTILIDAD
#===============================================================================
source "${0%/*}"/backup_mensajes.sh
#===============================================================================
# FUNCIONES DE CONFIGURACIÓN
#===============================================================================

verificar_dependencias() {
    local deps=("openssl" "tar" "gzip" "curl" "udevadm" "mount" "umount")
    local faltantes=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            faltantes+=("$dep")
        fi
    done
    
    if [ ${#faltantes[@]} -ne 0 ]; then
        salida_error "Dependencias faltantes: ${faltantes[*]}"
    fi
    
    mensaje_exito "Todas las dependencias están instaladas"
}

crear_directorios() {
    local dirs=("$CONFIG_DIR" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || salida_error "No se pudo crear el directorio $dir"
            mensaje_info "Directorio creado: $dir"
        fi
    done
}

#===============================================================================
# FUNCIONES DE AUTENTICACIÓN
#===============================================================================

verificar_firma_digital() {
    local usb_path="$1"
    local private_key="$(find "$usb_path" -maxdepth 1 -name '*.pem' | head -n 1)"
    local archivo_firmado="$usb_path/signature.sig"
    local challenge_file="$TEMP_DIR/challenge.txt"
    
    # Verificar que existan los archivos necesarios
    if [ ! -f "$private_key" ]; then
        mensaje_advertencia "No se encontró llave privada en la unidad USB"
        return 1
    fi
    
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        mensaje_advertencia "No se encontró archivo de llaves autorizadas"
        return 1
    fi
    
    # Generar desafío
    local challenge=$(openssl rand -hex 32)
    echo "$challenge" > "$challenge_file"
    
    mensaje_info "Generando desafío de autenticación..."
    
    # Firmar el desafío con la llave privada
    if ! openssl dgst -sha256 -sign "$private_key" -out "$archivo_firmado" "$challenge_file"; then
        mensaje_advertencia "Error al firmar el desafío"
        return 1
    fi
    
    # Extraer la llave pública
    local public_key_file="$TEMP_DIR/temp_public.pem"
    if ! openssl rsa -in "$private_key" -pubout -out "$public_key_file" 2>/dev/null; then
        mensaje_advertencia "Error al extraer llave pública"
        return 1
    fi
    
    # Verificar si la llave pública está autorizada
    local public_key_fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if ! grep -q "$public_key_fingerprint" "$SYSADMIN_KEYS"; then
        mensaje_advertencia "Llave pública no autorizada"
        rm -f "$public_key_file" "$challenge_file" "$archivo_firmado"
        return 1
    fi
    
    # Verificar la firma
    if openssl dgst -sha256 -verify "$public_key_file" -signature "$archivo_firmado" "$challenge_file"; then
        mensaje_exito "Autenticación por firma digital exitosa"
        rm -f "$public_key_file" "$challenge_file" "$archivo_firmado"
        return 0
    else
        mensaje_advertencia "Fallo en la verificación de firma digital"
        rm -f "$public_key_file" "$challenge_file" "$archivo_firmado"
        return 1
    fi
}

get_sysadmin_id() {
    local usb_path="$1"
    local sysadmin_id_file="$usb_path/sysadmin_id.txt"
    
    if [ -f "$sysadmin_id_file" ]; then
        cat "$sysadmin_id_file" | tr -d '\n\r'
    else
        echo "unknown"
    fi
}

#===============================================================================
# FUNCIONES DE TELEGRAM
#===============================================================================

load_telegram_config() {
 # El archivo debe existir
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        mensaje_advertencia "Archivo de configuración de Telegram no encontrado"
        return 1
    fi

    # Se extrae el token
    BOT_TOKEN=$(grep '^BOT_TOKEN=' "$TELEGRAM_CONFIG" \
                   | head -1 \
                   | cut -d'=' -f2- \
                   | tr -d '"')

    if [ -z "$BOT_TOKEN" ]; then
        mensaje_advertencia "Token del bot no configurado"
       return 1
    fi

    return 0
}

envio_notificacion() {
    local sysadmin_id="$1"
    local message="$2"
    local req_password="$3"
    
    if ! load_telegram_config; then
        mensaje_advertencia "No se pueden enviar notificaciones por Telegram"
        return 1
    fi
    
    # Obtener chat_id del sysadmin
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | tail -1 | cut -d':' -f2)
    
    if [ -z "$chat_id" ]; then
        mensaje_advertencia "Chat ID no encontrado para sysadmin: $sysadmin_id"
        return 1
    fi
    
    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local teclado=""
    
    if [ "$req_password" = "true" ]; then
        teclado=', "reply_markup": {"force_reply": true, "input_field_placeholder": "Ingrese la contraseña del servidor"}'
    fi
    
    local payload="{\"chat_id\": \"$chat_id\", \"text\": \"$message\"$teclado}"
    
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        mensaje_exito "Notificación enviada a $sysadmin_id"
        return 0
    else
        mensaje_advertencia "Error al enviar notificación: $response"
        return 1
    fi
}

esperar_contraseña() {
    local sysadmin_id="$1"
    local chat_id response u uid cid msj
    local start_time=$(date +%s)
    local timeout=300 
    local last_id=0

    # Determina el chat_id esperado
    chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | tail -n1 | cut -d: -f2)

    # Descartar mensajes anteriores
    response=$(curl -s \
      "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=0&limit=100&timeout=0")
    if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        last_id=$(echo "$response" | jq '[.result[].update_id] | max // 0')
    fi

    echo "ℹ Esperando nueva contraseña de $sysadmin_id..." >&2

    # Bucle de espera
    while [ $(( $(date +%s) - start_time )) -lt $timeout ]; do
        response=$(curl -s \
          "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$((last_id+1))&limit=1&timeout=0")

        # Validar JSON y extraer el primer update
        if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
            u=$(echo "$response" | jq -c '.result[0]?')
            if [ -n "$u" ]; then
                uid=$(echo "$u" | jq -r '.update_id')
                cid=$(echo "$u" | jq -r '.message.chat.id')
                msj=$(echo "$u" | jq -r '.message.text' 2>/dev/null | tr -d '\r\n')

                # Marcamos este update para no repetirlo
                last_id=$uid

                # Si es del chat correcto, devolvemos msj y salimos
                if [ "$cid" = "$chat_id" ] && [ -n "$msj" ]; then
                    echo -n "$msj"
                    return 0
                fi
            fi
        fi

        # No hay mensaje nuevo: esperar 5 s
        sleep 5
    done

    mensaje_advertencia "⚠ Timeout esperando contraseña"
    return 1
}




verificar_contrasena_servidor() {
    local provided_password="$1"
    # Verificar que se proporcione una contraseña
    provided_password=$(printf "%s" "$provided_password" \
                         | tr -d '\r\n' \
                         | xargs)

    # Leer y limpiar el hash almacenado
    if [ ! -f "$SERVER_HASH" ]; then
        salida_error "Archivo de hash del servidor no encontrado"
    fi
    local stored_hash
    stored_hash=$(tr -d ' \r\n' < "$SERVER_HASH")

    # Calcular hash de la contraseña proporcionada
    local provided_hash
    provided_hash=$(printf "%s" "$provided_password" \
                    | sha256sum \
                    | cut -d' ' -f1)

    # Depuración
    echo "DEBUG: hash almacenado: $stored_hash" >&2
    echo "DEBUG: hash recibido   : $provided_hash" >&2
    echo "DEBUG: contraseña limpia: '$provided_password'" >&2

    # 5) Comparación
    if [ "$stored_hash" = "$provided_hash" ]; then
        mensaje_exito "Contraseña verificada"
        return 0
    else
        mensaje_advertencia "Contraseña incorrecta"
        return 1
    fi
}

#===============================================================================
# FUNCIONES DE RESPALDO
#===============================================================================

read_backup_config() {
    local usb_path="$1"
    local config_file="$usb_path/backup_config.conf"
    
    if [ ! -f "$config_file" ]; then
        salida_error "Archivo de configuración de respaldo no encontrado en USB"
    fi
    
    source "$config_file"
    
    if [ -z "$BACKUP_DIRS" ]; then
        salida_error "No se especificaron directorios para respaldar"
    fi
    
    mensaje_info "Configuración de respaldo cargada desde USB"
}

crear_backup() {
    local backup_dirs="$1"
    local usb_path="$2"
    local server_password="$3"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local sysadmin_id=$(get_sysadmin_id "$usb_path")
    mensaje_info "Iniciando proceso de respaldo..."
    
    for dir in $backup_dirs; do
        if [ ! -d "$dir" ]; then
            mensaje_advertencia "Directorio no encontrado: $dir"
            continue
        fi
        
        local dir_name=$(basename "$dir")
        local backup_filename="${dir_name}_${timestamp}.tar.gz"
        local backup_path="$usb_path/$backup_filename"
        
        mensaje_info "Respaldando directorio: $dir"
        
        # Crear respaldo comprimido y cifrado
        if tar -czf - -C "$(dirname "$dir")" "$(basename "$dir")" | \
           openssl enc -aes-256-cbc -salt -k "$server_password" -out "$backup_path"; then
            
            local size=$(du -h "$backup_path" | cut -f1)
            mensaje_exito "Respaldo completado: $backup_filename ($size)"
            envio_notificacion "$sysadmin_id" \
                "✅ Respaldo completado exitosamente en servidor $(hostname). Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
        else
            mensaje_advertencia "Error al crear respaldo de: $dir"
            envio_notificacion "$sysadmin_id" \
                "❌ Respaldo cancelado: Error al crear respaldo por favor verifique integridad de dispositivo"
        fi
    done
    
    mensaje_exito "Proceso de respaldo finalizado"
}

#===============================================================================
# FUNCIÓN PRINCIPAL DE RESPALDO
#===============================================================================

process_usb_backup() {
    local usb_device="$1"
    local usb_path=""
    
    mensaje_info "Procesando dispositivo USB: $usb_device"
    # 
    # Encontrar punto de montaje usando findmnt
    usb_path=$(findmnt -n -o TARGET "/dev/$usb_device" 2>/dev/null || echo "")
    
    if [ -z "$usb_path" ]; then
        mensaje_advertencia "No se pudo encontrar el punto de montaje para $usb_device"
        return 1
    fi
    
    mensaje_info "USB montado en: $usb_path"
    
    # Verificar autenticación por firma digital
    if ! verificar_firma_digital "$usb_path"; then
        mensaje_advertencia "Fallo en autenticación por firma digital"
        return 1
    fi
    
    # Obtener ID del sysadmin
    local sysadmin_id=$(get_sysadmin_id "$usb_path")
    mensaje_info "Sysadmin identificado: $sysadmin_id"
    trap 'err=$?; \
          envio_notificacion "$sysadmin_id" \
            "❌ Error durante el proceso de respaldo (código $err). " \
            "false"; \
          return $err' ERR
          
    # Enviar notificación de inicio y solicitar contraseña
    envio_notificacion "$sysadmin_id" \
        "🔄 Iniciando proceso de respaldo en servidor $(hostname). Por favor, proporcione la contraseña del servidor." \
        "true"
    
    # Esperar contraseña del servidor
   # ─── Inicio bucle de intentos ───
    local server_password
    local intentos_max=5
    for intento in $(seq 1 $intentos_max); do
        # Esperar contraseña
        server_password=$(esperar_contraseña "$sysadmin_id")
        if [ -z "$server_password" ]; then
            # No respondió a tiempo: cancelamos
            envio_notificacion "$sysadmin_id" \
                "❌ Respaldo cancelado: No se recibió la contraseña en el tiempo límite."
            return 1
        fi

        # Verificar contraseña
        if verificar_contrasena_servidor "$server_password"; then
            # OK, salimos del bucle y continuamos
            break
        else
            # Falló el intento: notificar y reintentar (solicitamos de nuevo)
            envio_notificacion "$sysadmin_id" \
                "❌ Contraseña incorrecta. Vuelva a introducir la contraseña (Intento: $intento/$intentos_max)." \
                "true"
            # Si fue el último intento, cancelamos
            if [ "$intento" -eq "$intentos_max" ]; then
                envio_notificacion "$sysadmin_id" \
                    "❌ Respaldo cancelado: Se alcanzaron $intentos_max intentos incorrectos."
                return 1
            fi
            # Volvemos a iterar al siguiente intento
        fi
    done
 
    # Leer configuración de respaldo
    read_backup_config "$usb_path"
    
    # Enviar notificación de inicio de respaldo
    envio_notificacion "$sysadmin_id" \
        "✅ Autenticación exitosa. Iniciando respaldo de directorios: $BACKUP_DIRS"
    
    # Crear respaldos
    crear_backup "$BACKUP_DIRS" "$usb_path" "$server_password"
    
    # Enviar notificación de finalización
    
    mensaje_exito "Proceso de respaldo completado para $sysadmin_id"
}

#===============================================================================
# MONITOR DE DISPOSITIVOS USB
#===============================================================================

monitor_usb() {
    mensaje_info "Iniciando monitor de dispositivos USB..."
    
    udevadm monitor --kernel --subsystem-match=block | while read -r line; do
        if echo "$line" | grep -q "KERNEL\[.*\] add.*sd[a-z][0-9]"; then
            local device=$(echo "$line" | grep -o "sd[a-z][0-9]")
            mensaje_info "Nuevo dispositivo USB detectado: $device"
            
            # Esperar un momento para que el dispositivo se monte
            sleep 5
            
            # Procesar el respaldo
            process_usb_backup "$device"
        fi
    done
}

#===============================================================================
# FUNCIONES DE CONFIGURACIÓN
#===============================================================================

setup_initial_config() {
    mensaje_info "Configurando sistema inicial..."
    
    crear_directorios
    
    # Crear archivo de configuración del servidor si no existe
    if [ ! -f "$SERVER_CONFIG" ]; then
        cat > "$SERVER_CONFIG" << EOF
# Configuración del servidor de respaldo
SERVER_NAME=$(hostname)
SERVER_ID=$(hostname | sha256sum | cut -d' ' -f1 | head -c 8)
BACKUP_MAX_SIZE=1G
LOG_RETENTION_DAYS=30
EOF
        mensaje_info "Archivo de configuración del servidor creado"
    fi
    
    # Crear archivo de llaves autorizadas si no existe
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        touch "$SYSADMIN_KEYS"
        chmod 600 "$SYSADMIN_KEYS"
        mensaje_info "Archivo de llaves autorizadas creado"
    fi
    
    # Crear archivo de configuración de Telegram si no existe
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        cat > "$TELEGRAM_CONFIG" << EOF
# Configuración de Telegram
BOT_TOKEN=""
# Formato: sysadmin_id:chat_id
# admin1:123456789
# admin2:987654321
EOF
        chmod 600 "$TELEGRAM_CONFIG"
        mensaje_info "Archivo de configuración de Telegram creado"
    fi
    
    mensaje_exito "Configuración inicial completada"
}

#===============================================================================
# FUNCIONES DE UTILIDADES ADMINISTRATIVAS
#===============================================================================

add_sysadmin_key() {
    local public_key_file="$1"
    
    if [ ! -f "$public_key_file" ]; then
        salida_error "Archivo de llave pública no encontrado: $public_key_file"
    fi
    
    local fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if grep -q "$fingerprint" "$SYSADMIN_KEYS"; then
        mensaje_advertencia "La llave ya está autorizada"
        return 1
    fi
    
    echo "$fingerprint" >> "$SYSADMIN_KEYS"
    mensaje_exito "Llave pública autorizada: $fingerprint"
}

set_server_password() {
    local password="$1"
    
    if [ -z "$password" ]; then
        salida_error "Debe proporcionar una contraseña"
    fi
    
    local hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)
    echo "$hash" > "$SERVER_HASH"
    chmod 600 "$SERVER_HASH"
    mensaje_exito "Contraseña del servidor establecida"
}

mostrar_status() {
    echo -e "\n${AZUL}=== Estado del Sistema de Respaldo ===${NC}"
    echo -e "Servidor: $(hostname)"
    echo -e "Configuración: ${VERDE}$([ -f "$SERVER_CONFIG" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Llaves autorizadas: ${VERDE}$([ -f "$SYSADMIN_KEYS" ] && wc -l < "$SYSADMIN_KEYS" || echo "0")${NC}"
    echo -e "Contraseña configurada: ${VERDE}$([ -f "$SERVER_HASH" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Telegram configurado: ${VERDE}$([ -f "$TELEGRAM_CONFIG" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Servicio activo: ${VERDE}$(systemctl is-active backup-system.service 2>/dev/null || echo "inactivo")${NC}"
    echo
}

mostrar_ayuda(){
    echo "Sistema de Respaldo Automático - Administración de Redes"
    echo ""
    echo "Uso: $0 [OPCIÓN]"
    echo ""
    echo "OPCIONES:"
    echo "  -m o --monitor              Iniciar monitor de dispositivos USB"
    echo "  -s o --setup                Configuración inicial del sistema"
    echo "  -k o --add-key <archivo>    Autorizar llave pública de sysadmin"
    echo "  -p o --set-password <pass>  Establecer contraseña del servidor"
    echo "  -t o --status               Mostrar estado del sistema"
    echo "  -h o --help                 Mostrar esta ayuda"
    echo "EJEMPLOS:"
    echo "  $0 --monitor                        # Iniciar monitor"
    echo "  $0 --setup                          # Configuración inicial"
    echo "  $0 --add-key /path/to/public.pem    # Autorizar sysadmin"
    echo "  $0 --set-password "mi_password"     # Configurar contraseña"
    echo "  $0 --status                         # Mostrar estado del sistema"
    echo "  $0 --help                           # Mostrar ayuda"


    echo "ARCHIVOS DE CONFIGURACIÓN:"
    echo "  $SERVER_CONFIG      # Configuración del servidor"
    echo "  $SYSADMIN_KEYS      # Llaves públicas autorizadas"
    echo "  $SERVER_HASH        # Hash de contraseña del servidor"
    echo "  $TELEGRAM_CONFIG    # Configuración de Telegram"
}

#===============================================================================
# FUNCIÓN PRINCIPAL
#===============================================================================

main() {
    # Verificar que se ejecute como root
    if [ "$EUID" -ne 0 ]; then
        salida_error "Este script debe ejecutarse como root"
    fi
    test "$1" == "-m" || test "$1" == "--monitor" && { verificar_dependencias; crear_directorios; monitor_usb; exit; }
    test "$1" == "-s" || test "$1" == "--setup" && { verificar_dependencias; setup_initial_config; exit; }
    test "$1" == "-k" || test "$1" == "--add-key" && { test -z "$2" && salida_error "Debe especificar el archivo de llave pública"; add_sysadmin_key "$2"; exit; }
    test "$1" == "-p" || test "$1" == "--set-password" && { test -z "$2" && salida_error "Debe especificar la contraseña"; set_server_password "$2"; exit; }
    test "$1" == "-t" || test "$1" == "--status" && { mostrar_status; exit; }
    test "$1" == "-h" || test "$1" == "--help" && { mostrar_ayuda; exit; }
    test -z "$1" && { mostrar_ayuda; exit; } 
    salida_error "Opción no válida: $1. Use -h o --help para ver las opciones disponibles."
}

main "$@"