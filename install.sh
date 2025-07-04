#!/bin/bash

#========================#
# INSTALADOR DEL SISTEMA #
#========================#

source "${0%/*}"/backup_mensajes.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        salida_error "Este script debe ejecutarse como root"
    fi
}

instalar_dependencias() {
    mensaje_info "Instalando dependencias..."
    
    apt-get update || salida_error "Error al actualizar repositorios"
    
    local packages=("openssl" "curl" "udev" "systemd")
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            mensaje_info "Instalando $package..."
            apt-get install -y "$package" || salida_error "Error al instalar $package"
        else
            mensaje_exito "$package ya está instalado"
        fi
    done
}

setup_permisos() {
    mensaje_info "Configurando permisos..."
    
    chmod +x "$SCRIPT_DIR/backup_mensajes.sh"
    chmod +x "$SCRIPT_DIR/principal.sh"
    chmod +x "$SCRIPT_DIR/generar_llaves.sh"
    chmod +x "$SCRIPT_DIR/setup_telegram.sh"
    
    mensaje_exito "Permisos configurados"
}

crear_symlinks() {
    mensaje_info "Creando enlaces simbólicos..."
    
    ln -sf "$SCRIPT_DIR/backup_mensajes.sh" /usr/local/bin/backup_mensajes.sh
    ln -sf "$SCRIPT_DIR/principal.sh" /usr/local/bin/backup-system
    ln -sf "$SCRIPT_DIR/generar_llaves.sh" /usr/local/bin/backup-genkeys
    ln -sf "$SCRIPT_DIR/setup_telegram.sh" /usr/local/bin/backup-telegram
    
    mensaje_exito "Enlaces simbólicos creados en /usr/local/bin/"
}

install_systemd_service() {
    mensaje_info "Instalando servicio systemd..."
    
    if [ -f "$SCRIPT_DIR/backup-system.service" ]; then
        cp "$SCRIPT_DIR/backup-system.service" /etc/systemd/system/
        chmod 644 /etc/systemd/system/backup-system.service
        systemctl daemon-reload
        mensaje_exito "Servicio systemd instalado"
    else
        mensaje_advertencia "Archivo de servicio no encontrado"
    fi
}

instalar_sistema() {
    echo -e "${AZUL}=== Instalador del Sistema  ===${NC}\n"
    
    verificar_root
    instalar_dependencias
    setup_permisos
    crear_symlinks
    install_systemd_service
    
    # Ejecutar configuración inicial
    "$SCRIPT_DIR/principal.sh" --setup
    
    echo
    mensaje_exito "Instalación completada"
    
    echo -e "\n${AMARILLO}Próximos pasos:${NC}"
    echo "1. Configurar Telegram: backup-telegram --setup"
    echo "2. Generar llaves para sysadmins: backup-genkeys <sysadmin_id>"
    echo "3. Establecer contraseña del servidor: backup-system --set-password <password>"
    echo "4. Habilitar servicio: systemctl enable backup-system.service"
    echo "5. Iniciar servicio: systemctl start backup-system.service"
    echo "6. Verificar estado del sistema: backup-system --status"
    echo
}

desinstalar_sistema() {
    echo -e "${AMARILLO}¿Está seguro de desinstalar el sistema? (y/N)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        mensaje_info "Desinstalando sistema..."
        
        # Detener y deshabilitar servicio
        systemctl stop backup-system.service 2>/dev/null
        systemctl disable backup-system.service 2>/dev/null
        rm -f /etc/systemd/system/backup-system.service
        systemctl daemon-reload
        
        # Eliminar enlaces simbólicos
        rm -f /usr/local/bin/backup-system
        rm -f /usr/local/bin/backup-genkeys
        rm -f /usr/local/bin/backup-telegram
        rm -f /usr/local/bin/backup_mensajes.sh
        
        # Preguntar si eliminar configuración
        echo -e "${AMARILLO}¿Eliminar archivos de configuración? (y/N)${NC}"
        read -r response2
        
        if [[ "$response2" =~ ^[Yy]$ ]]; then
            rm -rf /etc/backup-system
            rm -rf /var/log/backup-system
            mensaje_exito "Configuración eliminada"
        fi
        
        mensaje_exito "Sistema desinstalado"
    else
        mensaje_info "Desinstalación cancelada"
    fi
}

mostrar_ayuda(){
    echo "Instalador del Sistema"
    echo ""
    echo "Uso: $0 [OPCIÓN]"
    echo ""
    echo "OPCIONES:"
    echo "    -i o --install      Instalar el sistema"
    echo "    -u o --uninstall    Desinstalar el sistema"
    echo "    -v o --version      Mostrar versión del script"
    echo "    -h o --help         Mostrar esta ayuda"
}

test "$1" == "-i" || test "$1" == "--install" && { instalar_sistema; exit; }
test "$1" == "-u" || test "$1" == "--uninstall" && { desinstalar_sistema; exit; }
test "$1" == "-v" || test "$1" == "--version" && { echo "Versión 1.0 "; exit; }
test "$1" == "-h" || test "$1" == "--help" && { mostrar_ayuda; exit; }
test -z "$1" && { mostrar_ayuda; exit; }
salida_error "Opción no válida: $1. Use -h o --help para ver las opciones disponibles."