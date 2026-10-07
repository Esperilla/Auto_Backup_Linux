#!/bin/bash

#==========================================#
# TELEGRAM SYSTEM CONFIGURATOR #
#==========================================#

source "${0%/*}"/messages.sh
CONFIG_DIR="/etc/backup-system"
TELEGRAM_CONFIG="$CONFIG_DIR/telegram.conf"

setup_telegram_bot() {
    echo -e "${BLUE}=== Telegram Bot Configuration ===${RESET}\n"
    
    echo "To configure Telegram notifications, you need:"
    echo "1. Create a bot on Telegram with @BotFather"
    echo "2. Obtain the bot token"
    echo "3. Obtain the sysadmin chat_id from: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo
    
    read -p "Telegram bot token? " bot_token
    
    if [ -z "$bot_token" ]; then
        error_exit "Bot token is required"
    fi
    
    # Create directory if it does not exist
    mkdir -p "$CONFIG_DIR"
    
    # Create configuration file
    cat > "$TELEGRAM_CONFIG" << EOF
# Telegram Bot configuration
BOT_TOKEN="$bot_token"

# Map sysadmin_id to chat_id
# Format: sysadmin_id:chat_id
EOF

    chmod 600 "$TELEGRAM_CONFIG"
    
    success_message "Base Telegram configuration created"
    
    # Agregar sysadmins
    while true; do
        echo
        read -p "Sysadmin ID (or 'done' to finish)? " sysadmin_id
        
        if [ "$sysadmin_id" = "done" ]; then
            break
        fi
        
        if [ -z "$sysadmin_id" ]; then
            continue
        fi
        
        read -p "Telegram chat ID for $sysadmin_id? " chat_id
        
        if [ -z "$chat_id" ]; then
            continue
        fi
        
        echo "$sysadmin_id:$chat_id" >> "$TELEGRAM_CONFIG"
        success_message "Sysadmin $sysadmin_id added"
    done
    
    echo
    success_message "Telegram configuration completed"
    info_message "Configuration file: $TELEGRAM_CONFIG"
}

test_telegram_notification() {
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        error_exit "Telegram configuration not found. Run setup first."
    fi
    
    local bot_token
    bot_token=$(grep '^BOT_TOKEN=' "$TELEGRAM_CONFIG" | head -1 | cut -d'=' -f2- | tr -d '"')
    if [ -z "$bot_token" ]; then
        error_exit "Bot token is not configured"
    fi
    
    echo -e "${BLUE}=== Notification Test ===${RESET}\n"
    
    read -p "Sysadmin ID to test? " sysadmin_id
    
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | cut -d':' -f2)
    
    if [ -z "$chat_id" ]; then
        error_exit "Chat ID not found for sysadmin: $sysadmin_id"
    fi
    
    local url="https://api.telegram.org/bot$bot_token/sendMessage"
    local message="🔧 Automatic backup system test from server $(hostname)"
    local payload
    payload=$(jq -cn --arg chat_id "$chat_id" --arg text "$message" \
        '{chat_id: $chat_id, text: $text}')
    
    info_message "Sending test message..."
    
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        success_message "Test notification sent successfully"
    else
        error_exit "Error sending notification: $response"
    fi
}

show_help(){
    echo "Telegram System Configurator"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "OPTIONS:"
    echo "    -s or --setup    Configure bot and sysadmins"
    echo "    -t or --test     Test notifications"
    echo "    -v or --version  Show script version"
    echo "    -h or --help     Show this help"
    echo ""
    echo "Steps to obtain chat_id:"
    echo "    1. Start a conversation with your bot"
    echo "    2. Send any message to the bot"
    echo "    3. Visit: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "    4. Look for "chat":{"id":XXXXXXXXX} in the response"
}

test "$1" == "-s" || test "$1" == "--setup" && { setup_telegram_bot; exit; }
test "$1" == "-t" || test "$1" == "--test" && { test_telegram_notification; exit; }
test "$1" == "-v" || test "$1" == "--version" && { echo "Version 1.0"; exit; }
test "$1" == "-h" || test "$1" == "--help" && { show_help; exit; }
test -z "$1" && { show_help; exit; }
error_exit "Invalid option: $1. Use -h or --help to see the available options."