#!/bin/bash

#=====================================#
# GENERADOR DE LLAVES PARA EL SISTEMA #
#=====================================#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${0%/*}"/backup_mensajes.sh

generate_sysadmin_keys() {
    local sysadmin_id="$1"
    local output_dir="${2:-./keys}"
    
    if [ -z "$sysadmin_id" ]; then
        salida_error "Debe especificar el ID del sysadmin"
    fi
    
    mkdir -p "$output_dir"
    
    local private_key="$output_dir/${sysadmin_id}_private.pem"
    local public_key="$output_dir/${sysadmin_id}_public.pem"
    
    mensaje_info "Generando par de llaves para sysadmin: $sysadmin_id"
    
    # Generar llave privada
    openssl genrsa -out "$private_key" 2048 || salida_error "Error al generar llave privada"
    chmod 600 "$private_key"
    
    # Extraer llave pública
    openssl rsa -in "$private_key" -pubout -out "$public_key" || salida_error "Error al extraer llave pública"
    
    # Crear archivo de ID del sysadmin
    echo "$sysadmin_id" > "$output_dir/sysadmin_id.txt"
    
    mensaje_exito "Llaves generadas exitosamente:"
    echo "  - Llave privada: $private_key"
    echo "  - Llave pública: $public_key"
    echo "  - ID del sysadmin: $output_dir/sysadmin_id.txt"
    
    mensaje_info "Copie $private_key y sysadmin_id.txt a la unidad USB"
    mensaje_info "Autorice $public_key en el servidor con: backup-system --add-key $public_key"
}

mostrar_ayuda() {
    echo "Generador de Llaves para el Sistema"
    echo ""
    echo "Uso: $0 <sysadmin_id>"
    echo "Ejemplo: $0 sysadmin123"
}

test "$1" == "-h" || test "$1" == "--help" && { mostrar_ayuda; exit; }
test -z "$1" && { mostrar_ayuda; exit; }

generate_sysadmin_keys "$1" "$2"