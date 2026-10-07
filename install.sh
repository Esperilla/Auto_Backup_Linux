#!/bin/bash

#========================#
# SYSTEM INSTALLER #
#========================#

source "${0%/*}"/messages.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root"
    fi
}

install_dependencies() {
    info_message "Installing dependencies..."
    
    apt-get update || error_exit "Error updating repositories"
    
    local packages=("openssl" "curl" "udev" "systemd" "jq" "util-linux" "coreutils")
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            info_message "Installing $package..."
            apt-get install -y "$package" || error_exit "Error installing $package"
        else
            success_message "$package is already installed"
        fi
    done
}

setup_permissions() {
    info_message "Configuring permissions..."
    
    chmod +x "$SCRIPT_DIR/messages.sh"
    chmod +x "$SCRIPT_DIR/main.sh"
    chmod +x "$SCRIPT_DIR/gen_keys.sh"
    chmod +x "$SCRIPT_DIR/setup_telegram.sh"
    
    success_message "Permissions configured"
}

create_symlinks() {
    info_message "Creating symbolic links..."
    
    ln -sf "$SCRIPT_DIR/messages.sh" /usr/local/bin/messages.sh
    ln -sf "$SCRIPT_DIR/main.sh" /usr/local/bin/backup-system
    ln -sf "$SCRIPT_DIR/gen_keys.sh" /usr/local/bin/backup-genkeys
    ln -sf "$SCRIPT_DIR/setup_telegram.sh" /usr/local/bin/backup-telegram
    
    success_message "Symbolic links created in /usr/local/bin/"
}

install_systemd_service() {
    info_message "Installing systemd service..."
    
    if [ -f "$SCRIPT_DIR/backup-system.service" ]; then
        cp "$SCRIPT_DIR/backup-system.service" /etc/systemd/system/
        chmod 644 /etc/systemd/system/backup-system.service
        systemctl daemon-reload
        success_message "systemd service installed"
    else
        warning_message "Service file not found"
    fi
}

install_system() {
    echo -e "${BLUE}=== System Installer ===${RESET}\n"
    
    check_root
    install_dependencies
    setup_permissions
    create_symlinks
    install_systemd_service
    
    # Run initial configuration
    "$SCRIPT_DIR/main.sh" --setup
    
    echo
    success_message "Installation completed"
    
    echo -e "\n${YELLOW}Next steps:${RESET}"
    echo "1. Configure Telegram: backup-telegram --setup"
    echo "2. Generate keys for sysadmins: backup-genkeys <sysadmin_id>"
    echo "3. Set the server password: backup-system --set-password <password>"
    echo "4. Enable the service: systemctl enable backup-system.service"
    echo "5. Start the service: systemctl start backup-system.service"
    echo "6. Check system status: backup-system --status"
    echo
}

uninstall_system() {
    echo -e "${YELLOW}Are you sure you want to uninstall the system? (y/N)${RESET}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info_message "Uninstalling system..."
        
        # Stop and disable service
        systemctl stop backup-system.service 2>/dev/null
        systemctl disable backup-system.service 2>/dev/null
        rm -f /etc/systemd/system/backup-system.service
        systemctl daemon-reload
        
        # Remove symbolic links
        rm -f /usr/local/bin/backup-system
        rm -f /usr/local/bin/backup-genkeys
        rm -f /usr/local/bin/backup-telegram
        rm -f /usr/local/bin/messages.sh
        
        # Ask whether to remove configuration
        echo -e "${YELLOW}Remove configuration files? (y/N)${RESET}"
        read -r response2
        
        if [[ "$response2" =~ ^[Yy]$ ]]; then
            rm -rf /etc/backup-system
            rm -rf /var/log/backup-system
            success_message "Configuration removed"
        fi
        
        success_message "System uninstalled"
    else
        info_message "Uninstallation canceled"
    fi
}

show_help(){
    echo "System Installer"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "OPTIONS:"
    echo "    -i or --install      Install the system"
    echo "    -u or --uninstall    Uninstall the system"
    echo "    -v or --version      Show script version"
    echo "    -h or --help         Show this help"
}

test "$1" == "-i" || test "$1" == "--install" && { install_system; exit; }
test "$1" == "-u" || test "$1" == "--uninstall" && { uninstall_system; exit; }
test "$1" == "-v" || test "$1" == "--version" && { echo "Version 1.0"; exit; }
test "$1" == "-h" || test "$1" == "--help" && { show_help; exit; }
test -z "$1" && { show_help; exit; }
error_exit "Invalid option: $1. Use -h or --help to see the available options."