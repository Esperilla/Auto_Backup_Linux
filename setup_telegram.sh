#!/bin/bash

#==========================================#
# CONFIGURADOR DE TELEGRAM PARA EL SISTEMA #
#==========================================#

source "${0%/*}"/backup_mensajes.sh
CONFIG_DIR="/etc/backup-system"
TELEGRAM_CONFIG="$CONFIG_DIR/telegram.conf"

setup_telegram_bot() {
    echo -e "${AZUL}=== Configuración del Bot de Telegram ===${NC}\n"
    
    echo "Para configurar las notificaciones de Telegram necesitas:"
    echo "1. Crear un bot en Telegram con @BotFather"
    echo "2. Obtener el token del bot"
    echo "3. Obtener el chat_id del sysadmin desde: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo
    
    read -p "¿Token del bot de Telegram? " bot_token
    
    if [ -z "$bot_token" ]; then
        salida_error "Token del bot es requerido"
    fi
    
    # Crear directorio si no existe
    mkdir -p "$CONFIG_DIR"
    
    # Crear archivo de configuración
    cat > "$TELEGRAM_CONFIG" << EOF
# Configuración de Telegram Bot
BOT_TOKEN="$bot_token"

# Mapeo de sysadmin_id a chat_id
# Formato: sysadmin_id:chat_id
EOF

    chmod 600 "$TELEGRAM_CONFIG"
    
    mensaje_exito "Configuración base de Telegram creada"
    
    # Agregar sysadmins
    while true; do
        echo
        read -p "¿ID del sysadmin (o 'fin' para terminar)? " sysadmin_id
        
        if [ "$sysadmin_id" = "fin" ]; then
            break
        fi
        
        if [ -z "$sysadmin_id" ]; then
            continue
        fi
        
        read -p "¿Chat ID de Telegram para $sysadmin_id? " chat_id
        
        if [ -z "$chat_id" ]; then
            continue
        fi
        
        echo "$sysadmin_id:$chat_id" >> "$TELEGRAM_CONFIG"
        mensaje_exito "Sysadmin $sysadmin_id agregado"
    done
    
    echo
    mensaje_exito "Configuración de Telegram completada"
    mensaje_info "Archivo de configuración: $TELEGRAM_CONFIG"
}

test_telegram_notification() {
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        salida_error "Configuración de Telegram no encontrada. Ejecute primero la configuración."
    fi
    
    source "$TELEGRAM_CONFIG"
    
    if [ -z "$BOT_TOKEN" ]; then
        salida_error "Token del bot no configurado"
    fi
    
    echo -e "${AZUL}=== Prueba de Notificaciones ===${NC}\n"
    
    read -p "¿ID del sysadmin a probar? " sysadmin_id
    
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | cut -d':' -f2)
    
    if [ -z "$chat_id" ]; then
        salida_error "Chat ID no encontrado para sysadmin: $sysadmin_id"
    fi
    
    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local message="🔧 Prueba del sistema de respaldo automático desde servidor $(hostname)"
    local payload="{\"chat_id\": \"$chat_id\", \"text\": \"$message\"}"
    
    mensaje_info "Enviando mensaje de prueba..."
    
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        mensaje_exito "Notificación de prueba enviada exitosamente"
    else
        salida_error "Error al enviar notificación: $response"
    fi
}

mostrar_ayuda(){
    echo "Configurador de Telegram para el Sistema"
    echo ""
    echo "Uso: $0 [OPCIÓN]"
    echo ""
    echo "OPCIONES:"
    echo "    -s o --setup    Configurar bot y sysadmins"
    echo "    -t o --test     Probar notificaciones"
    echo "    -v o --version  Mostrar versión del script"
    echo "    -h o --help     Mostrar esta ayuda"
    echo ""
    echo "Pasos para obtener chat_id:"
    echo "    1. Inicie una conversación con su bot"
    echo "    2. Envíe cualquier mensaje al bot"
    echo "    3. Visite: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "    4. Busque el "chat":{"id":XXXXXXXXX} en la respuesta"
}

test "$1" == "-s" || test "$1" == "--setup" && { setup_telegram_bot; exit; }
test "$1" == "-t" || test "$1" == "--test" && { test_telegram_notification; exit; }
test "$1" == "-v" || test "$1" == "--version" && { echo "Versión 1.0 "; exit; }
test "$1" == "-h" || test "$1" == "--help" && { mostrar_ayuda; exit; }
test -z "$1" && { mostrar_ayuda; exit; }
salida_error "Opción no válida: $1. Use -h o --help para ver las opciones disponibles."