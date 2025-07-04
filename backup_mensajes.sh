#!/bin/bash

#==================================#
# SCRIPT PARA MENSAJES DEL SISTEMA #
#==================================#
LOG_DIR="/var/log/backup-system"

ROJO='\033[0;31m'      
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m'

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/backup.log"
}

mensaje_exito() {
    log_message "INFO" "$1"
    echo -e "${VERDE}✓ $1${NC}"
}

mensaje_info() {
    log_message "INFO" "$1"
    echo -e "${AZUL}ℹ $1${NC}"
}

salida_error() {
    log_message "ERROR" "$1"
    echo -e "${ROJO}ERROR: $1${NC}" >&2
    exit 1
}

mensaje_advertencia() {
    log_message "WARNING" "$1"
    echo -e "${AMARILLO}⚠ $1${NC}"
}