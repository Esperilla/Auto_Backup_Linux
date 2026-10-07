#!/bin/bash

#===================================================================#
# AUTOMATIC BACKUP SYSTEM WITH AUTHENTICATION AND NOTIFICATIONS #
#===================================================================#

source "${0%/*}"/messages.sh
set -o pipefail

# Global configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/backup-system"
#LOG_DIR="/var/log/backup-system"
TEMP_DIR="/tmp/backup-system"
LOCK_FILE="/run/lock/backup-system.lock"
USB_MOUNT_BASE="/media"

# Configuration files
SERVER_CONFIG="$CONFIG_DIR/server.conf"
SYSADMIN_KEYS="$CONFIG_DIR/authorized_keys"
SERVER_HASH="$CONFIG_DIR/server_hash"
TELEGRAM_CONFIG="$CONFIG_DIR/telegram.conf"

#----------------------------#
# CONFIGURATION FUNCTIONS #
#----------------------------#

check_dependencies() {
    local deps=("openssl" "tar" "gzip" "curl" "udevadm" "findmnt" "mount" "umount" "jq" "sha256sum" "df" "stat" "flock")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error_exit "Missing dependencies: ${missing[*]}"
    fi
    
    success_message "All dependencies are installed"
}

parse_size_bytes() {
    local value="${1^^}"
    local number="${value%[KMGT]}"
    local suffix="${value:${#number}:1}"

    [[ "$number" =~ ^[0-9]+$ ]] || return 1
    case "$suffix" in
        "") printf '%s\n' "$number" ;;
        K) printf '%s\n' $((number * 1024)) ;;
        M) printf '%s\n' $((number * 1024 * 1024)) ;;
        G) printf '%s\n' $((number * 1024 * 1024 * 1024)) ;;
        T) printf '%s\n' $((number * 1024 * 1024 * 1024 * 1024)) ;;
        *) return 1 ;;
    esac
}

load_server_limits() {
    local max_size retention
    max_size=$(grep '^BACKUP_MAX_SIZE=' "$SERVER_CONFIG" 2>/dev/null | tail -n 1 | cut -d= -f2-)
    retention=$(grep '^LOG_RETENTION_DAYS=' "$SERVER_CONFIG" 2>/dev/null | tail -n 1 | cut -d= -f2-)
    BACKUP_MAX_BYTES=$(parse_size_bytes "${max_size:-1G}") || error_exit "Invalid BACKUP_MAX_SIZE: ${max_size:-empty}"
    [[ "$retention" =~ ^[0-9]+$ ]] || error_exit "Invalid LOG_RETENTION_DAYS: ${retention:-empty}"
    LOG_RETENTION_DAYS="$retention"
}

cleanup_old_logs() {
    local current_log="$LOG_DIR/backup.log"
    local today_epoch
    today_epoch=$(date -d today +%s)
    if [ -f "$current_log" ] && [ "$(stat -c '%Y' "$current_log")" -lt "$today_epoch" ]; then
        mv -f "$current_log" "$LOG_DIR/backup.log.$(date -d yesterday +%Y%m%d)" || \
            warning_message "Could not rotate the current log file"
    fi
    find "$LOG_DIR" -maxdepth 1 -type f -name 'backup.log.*' \
        -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

acquire_backup_lock() {
    mkdir -p "$(dirname "$LOCK_FILE")" || return 1
    exec 9>"$LOCK_FILE" || return 1
    if ! flock -n 9; then
        exec 9>&-
        return 1
    fi
    return 0
}

release_backup_lock() {
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

create_directories() {
    local dirs=("$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || error_exit "Could not create directory $dir"
            info_message "Directory created: $dir"
        fi
    done
    chmod 700 "$CONFIG_DIR" "$TEMP_DIR" "$LOG_DIR"
}

#----------------------------#
# AUTHENTICATION FUNCTIONS #
#----------------------------#

verify_digital_signature() {
    local usb_path="$1"
    local private_key="$(find "$usb_path" -maxdepth 1 -name '*.pem' | head -n 1)"
    local signed_file="$usb_path/signature.sig"
    local challenge_file
    challenge_file=$(mktemp "$TEMP_DIR/challenge.XXXXXX") || {
        warning_message "Could not create authentication challenge"
        return 1
    }
    
    # Verify that the required files exist
    if [ ! -f "$private_key" ]; then
        warning_message "No private key found on the USB drive"
        return 1
    fi
    
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        warning_message "No authorized keys file found"
        return 1
    fi
    
    # Generate challenge
    local challenge=$(openssl rand -hex 32)
    echo "$challenge" > "$challenge_file"
    
    info_message "Generating authentication challenge..."
    
    # Sign the challenge with the private key
    if ! openssl dgst -sha256 -sign "$private_key" -out "$signed_file" "$challenge_file"; then
        warning_message "Error signing the challenge"
        return 1
    fi
    
    # Extract the public key
    local public_key_file
    public_key_file=$(mktemp "$TEMP_DIR/public.XXXXXX") || {
        rm -f "$challenge_file"
        warning_message "Could not create temporary public key file"
        return 1
    }
    if ! openssl rsa -in "$private_key" -pubout -out "$public_key_file" 2>/dev/null; then
        warning_message "Error extracting public key"
        return 1
    fi
    
    # Verify whether the public key is authorized
    local public_key_fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if ! grep -q "$public_key_fingerprint" "$SYSADMIN_KEYS"; then
        warning_message "Public key is not authorized"
        rm -f "$public_key_file" "$challenge_file" "$signed_file"
        return 1
    fi
    
    # Verificar la firma
    if openssl dgst -sha256 -verify "$public_key_file" -signature "$signed_file" "$challenge_file"; then
        success_message "Digital signature authentication successful"
        rm -f "$public_key_file" "$challenge_file" "$signed_file"
        return 0
    else
        warning_message "Digital signature verification failed"
        rm -f "$public_key_file" "$challenge_file" "$signed_file"
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

#-----------------------#
# TELEGRAM FUNCTIONS #
#-----------------------#

load_telegram_config() {
 # The file must exist
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        warning_message "Telegram configuration file not found"
        return 1
    fi

    # Extract the token
    BOT_TOKEN=$(grep '^BOT_TOKEN=' "$TELEGRAM_CONFIG" \
                   | head -1 \
                   | cut -d'=' -f2- \
                   | tr -d '"')

    if [ -z "$BOT_TOKEN" ]; then
        warning_message "Bot token is not configured"
       return 1
    fi

    return 0
}

send_notification() {
    local sysadmin_id="$1"
    local message="$2"
    local req_password="$3"
    
    if ! load_telegram_config; then
        warning_message "Telegram notifications cannot be sent"
        return 1
    fi
    
    # Get the sysadmin chat_id
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | tail -1 | cut -d':' -f2)
    
    if [ -z "$chat_id" ]; then
        warning_message "Chat ID not found for sysadmin: $sysadmin_id"
        return 1
    fi
    
    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local keyboard=""
    
    if [ "$req_password" = "true" ]; then
        keyboard=', "reply_markup": {"force_reply": true, "input_field_placeholder": "Enter the server password"}'
    fi
    
    local payload
    if [ "$req_password" = "true" ]; then
        payload=$(jq -cn --arg chat_id "$chat_id" --arg text "$message" \
            '{chat_id: $chat_id, text: $text, reply_markup: {force_reply: true, input_field_placeholder: "Enter the server password"}}')
    else
        payload=$(jq -cn --arg chat_id "$chat_id" --arg text "$message" \
            '{chat_id: $chat_id, text: $text}')
    fi
    
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        success_message "Notification sent to $sysadmin_id"
        return 0
    else
        warning_message "Error sending notification: $response"
        return 1
    fi
}

wait_for_password() {
    local sysadmin_id="$1"
    local chat_id response u uid cid message_text
    local start_time=$(date +%s)
    local timeout=300 
    local last_id=0

    # Determine the expected chat_id
    chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | tail -n1 | cut -d: -f2)

    # Discard previous messages
    response=$(curl -s \
      "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=0&limit=100&timeout=0")
    if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        last_id=$(echo "$response" | jq '[.result[].update_id] | max // 0')
    fi

    echo "ℹ Waiting for a new password from $sysadmin_id..." >&2

    # Wait loop
    while [ $(( $(date +%s) - start_time )) -lt $timeout ]; do
        response=$(curl -s \
          "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$((last_id+1))&limit=1&timeout=0")

        # Validar JSON y extraer el primer update
        if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
            u=$(echo "$response" | jq -c '.result[0] // empty')
            if [ -n "$u" ] && [ "$u" != "null" ]; then
                uid=$(echo "$u" | jq -r '.update_id')
                cid=$(echo "$u" | jq -r '.message.chat.id')
                message_text=$(echo "$u" | jq -r '.message.text' 2>/dev/null | tr -d '\r\n')

                # Mark this update so it is not repeated
                last_id=$uid

                # If it is from the correct chat, return the message and exit
                if [ "$cid" = "$chat_id" ] && [ -n "$message_text" ]; then
                    echo -n "$message_text"
                    return 0
                fi
            fi
        fi

        # No new message: wait 5 seconds
        sleep 5
    done

    warning_message "⚠ Password wait timed out"
    return 1
}

verify_server_password() {
    local provided_password="$1"
    # Verify that a password was provided
    provided_password=$(printf "%s" "$provided_password" \
                         | tr -d '\r\n' \
                         | xargs)

    # Read and clean the stored hash
    if [ ! -f "$SERVER_HASH" ]; then
        error_exit "Server hash file not found"
    fi
    local stored_hash
    stored_hash=$(tr -d ' \r\n' < "$SERVER_HASH")

    # Calculate the hash of the provided password
    local provided_hash
    provided_hash=$(printf "%s" "$provided_password" \
                    | sha256sum \
                    | cut -d' ' -f1)

    if [ "$stored_hash" = "$provided_hash" ]; then
        success_message "Password verified"
        return 0
    else
        warning_message "Incorrect password"
        return 1
    fi
}

#-----------------------#
# BACKUP FUNCTIONS #
#-----------------------#

read_backup_config() {
    local usb_path="$1"
    local config_file="$usb_path/backup_config.conf"
    
    if [ ! -f "$config_file" ]; then
        error_exit "Backup configuration file not found on USB"
    fi
    
    BACKUP_DIRS=""
    BACKUP_NAME=""
    EXCLUDE_PATTERNS=""
    SYSADMIN_NAME=""
    BACKUP_DESCRIPTION=""

    while IFS='=' read -r key value || [ -n "$key" ]; do
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        [ -z "$key" ] || [ "${key#\#}" != "$key" ] || [ -z "$value" ] && continue
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [ "${value:0:1}" = '"' ] && [ "${value: -1}" = '"' ]; then
            value="${value:1:${#value}-2}"
        elif [ "${value:0:1}" = "'" ] && [ "${value: -1}" = "'" ]; then
            value="${value:1:${#value}-2}"
        fi
        case "$key" in
            BACKUP_DIRS|BACKUP_NAME|EXCLUDE_PATTERNS|SYSADMIN_NAME|BACKUP_DESCRIPTION)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                warning_message "Ignoring unsupported configuration key: $key"
                ;;
        esac
    done < "$config_file"
    
    if [ -z "$BACKUP_DIRS" ]; then
        error_exit "No backup directories were specified"
    fi
    
    info_message "Backup configuration loaded from USB"
}

create_backup() {
    local backup_dirs="$1"
    local usb_path="$2"
    local server_password="$3"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local sysadmin_id=$(get_sysadmin_id "$usb_path")
    local available_bytes

    info_message "Starting backup process..."
    
    for dir in $backup_dirs; do
        if [ ! -d "$dir" ]; then
            warning_message "Directory not found: $dir"
            continue
        fi
        
        local dir_name=$(basename "$dir")
        local backup_prefix="${BACKUP_NAME:-backup}"
        local backup_filename="${backup_prefix}_${dir_name}_${timestamp}.tar.gz.enc"
        local backup_path="$usb_path/$backup_filename"
        local temp_path
        temp_path=$(mktemp "$usb_path/.backup.XXXXXX") || {
            warning_message "Could not create temporary backup file on USB"
            continue
        }
        
        info_message "Backing up directory: $dir"

        available_bytes=$(df -Pk "$usb_path" | awk 'NR==2 {print $4 * 1024}')
        if ! [[ "$available_bytes" =~ ^[0-9]+$ ]] || [ "$available_bytes" -lt "$BACKUP_MAX_BYTES" ]; then
            rm -f "$temp_path"
            warning_message "Insufficient free space for configured backup limit on: $usb_path"
            send_notification "$sysadmin_id" \
                "❌ Backup canceled: insufficient free space on the USB device."
            continue
        fi
        
        local tar_args=()
        for pattern in $EXCLUDE_PATTERNS; do
            tar_args+=(--exclude="$pattern")
        done

        if tar -czf - "${tar_args[@]}" -C "$(dirname "$dir")" "$(basename "$dir")" | \
           openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass fd:3 -out "$temp_path" 3<<<"$server_password" &&
           [ -s "$temp_path" ] &&
           [ "$(stat -c '%s' "$temp_path")" -le "$BACKUP_MAX_BYTES" ]; then
            mv -f "$temp_path" "$backup_path" || {
                rm -f "$temp_path"
                warning_message "Could not finalize backup of: $dir"
                continue
            }
            
            local size=$(du -h "$backup_path" | cut -f1)
            success_message "Backup completed: $backup_filename ($size)"
            send_notification "$sysadmin_id" \
                "✅ Backup completed successfully on server $(hostname). Date: $(date '+%Y-%m-%d %H:%M:%S')"
        else
            rm -f "$temp_path"
            warning_message "Error creating backup of: $dir or configured size limit exceeded"
            send_notification "$sysadmin_id" \
                "❌ Backup canceled: Error creating backup; please check device integrity"
        fi
    done
    
    success_message "Backup process finished"
}

#-------------------------------#
# MAIN BACKUP FUNCTION #
#-------------------------------#

_process_usb_backup() {
    local usb_device="$1"
    local usb_path=""
    
    info_message "Processing USB device: $usb_device"
    # 
    # Find the mount point using findmnt
    usb_path=$(findmnt -n -o TARGET "/dev/$usb_device" 2>/dev/null || echo "")
    
    if [ -z "$usb_path" ]; then
        warning_message "Could not find the mount point for $usb_device"
        return 1
    fi

    if [ ! -w "$usb_path" ]; then
        warning_message "USB mount is not writable: $usb_path"
        return 1
    fi
    
    info_message "USB mounted at: $usb_path"
    
    # Verify digital signature authentication
    if ! verify_digital_signature "$usb_path"; then
        warning_message "Digital signature authentication failed"
        return 1
    fi
    
    # Get the sysadmin ID
    local sysadmin_id=$(get_sysadmin_id "$usb_path")
    info_message "Sysadmin identified: $sysadmin_id"
    # Send start notification and request the password
    send_notification "$sysadmin_id" \
        "🔄 Starting backup process on server $(hostname). Please provide the server password." \
        "true"
    
    # Wait for the server password
   # ─── Start attempt loop ───
    local server_password
    local max_attempts=5
    for intento in $(seq 1 $max_attempts); do
        # Wait for password
        server_password=$(wait_for_password "$sysadmin_id")
        if [ -z "$server_password" ]; then
            # No response in time: cancel
            send_notification "$sysadmin_id" \
                "❌ Backup canceled: No password was received before the timeout."
            return 1
        fi

        # Verify password
        if verify_server_password "$server_password"; then
            # OK, exit the loop and continue
            break
        else
            # Attempt failed: notify and retry (request again)
            send_notification "$sysadmin_id" \
                "❌ Incorrect password. Enter the password again (Attempt: $intento/$max_attempts)." \
                "true"
            # If this was the last attempt, cancel
            if [ "$intento" -eq "$max_attempts" ]; then
                send_notification "$sysadmin_id" \
                    "❌ Backup canceled: $max_attempts incorrect attempts reached."
                return 1
            fi
            # Continue with the next attempt
        fi
    done
 
    # Read backup configuration
    read_backup_config "$usb_path"
    
    # Send backup start notification
    send_notification "$sysadmin_id" \
        "✅ Authentication successful. Starting backup of directories: $BACKUP_DIRS"
    
    # Create backups
    create_backup "$BACKUP_DIRS" "$usb_path" "$server_password"
    
    # Send completion notification
    
    success_message "Backup process completed for $sysadmin_id"
}

process_usb_backup() {
    local usb_device="$1"
    if ! acquire_backup_lock; then
        warning_message "Another backup is already in progress; ignoring device: $usb_device"
        return 0
    fi

    load_server_limits
    cleanup_old_logs
    _process_usb_backup "$usb_device"
    local status=$?
    release_backup_lock
    return "$status"
}

#=============================#
# USB DEVICE MONITOR #
#=============================#

monitor_usb() {
    info_message "Starting USB device monitor..."
    load_server_limits
    cleanup_old_logs
    
    udevadm monitor --kernel --subsystem-match=block | while read -r line; do
        if echo "$line" | grep -q "KERNEL\[.*\] add.*sd[a-z][0-9]"; then
            local device=$(echo "$line" | grep -o "sd[a-z][0-9]")
            info_message "New USB device detected: $device"
            
            # Wait briefly for the device to mount
            sleep 5
            
            if [ "$(udevadm info --query=property --name="/dev/$device" 2>/dev/null | awk -F= '$1=="ID_BUS"{print $2; exit}')" != "usb" ]; then
                info_message "Ignoring non-USB block device: $device"
                continue
            fi

            # Process the backup
            process_usb_backup "$device"
        fi
    done
}

#============================#
# CONFIGURATION FUNCTIONS #
#============================#

setup_initial_config() {
    info_message "Configuring initial system setup..."
    
    create_directories
    
    # Create the server configuration file if it does not exist
    if [ ! -f "$SERVER_CONFIG" ]; then
        cat > "$SERVER_CONFIG" << EOF
# Backup server configuration
SERVER_NAME=$(hostname)
SERVER_ID=$(hostname | sha256sum | cut -d' ' -f1 | head -c 8)
BACKUP_MAX_SIZE=1G
LOG_RETENTION_DAYS=30
EOF
        info_message "Server configuration file created"
    fi
    
    # Create the authorized keys file if it does not exist
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        touch "$SYSADMIN_KEYS"
        chmod 600 "$SYSADMIN_KEYS"
        info_message "Authorized keys file created"
    fi
    
    # Create the Telegram configuration file if it does not exist
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        cat > "$TELEGRAM_CONFIG" << EOF
# Telegram configuration
BOT_TOKEN=""
# Formato: sysadmin_id:chat_id
# admin1:123456789
# admin2:987654321
EOF
        chmod 600 "$TELEGRAM_CONFIG"
        info_message "Telegram configuration file created"
    fi
    
    success_message "Initial configuration completed"
}

#=========================================#
# ADMINISTRATIVE UTILITY FUNCTIONS #
#=========================================#

add_sysadmin_key() {
    local public_key_file="$1"
    
    if [ ! -f "$public_key_file" ]; then
        error_exit "Public key file not found: $public_key_file"
    fi
    
    local fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if grep -q "$fingerprint" "$SYSADMIN_KEYS"; then
        warning_message "The key is already authorized"
        return 1
    fi
    
    echo "$fingerprint" >> "$SYSADMIN_KEYS"
    success_message "Public key authorized: $fingerprint"
}

set_server_password() {
    local password="$1"
    
    if [ -z "$password" ]; then
        error_exit "You must provide a password"
    fi
    
    local hash
    hash=$(printf '%s' "$password" | sha256sum | cut -d' ' -f1)
    echo "$hash" > "$SERVER_HASH"
    chmod 600 "$SERVER_HASH"
    success_message "Server password set"
}

show_status() {
    echo -e "\n${BLUE}=== Backup System Status ===${RESET}"
    echo -e "Server: $(hostname)"
    echo -e "Configuration: ${GREEN}$([ -f "$SERVER_CONFIG" ] && echo "✓" || echo "✗")${RESET}"
    echo -e "Authorized keys: ${GREEN}$([ -f "$SYSADMIN_KEYS" ] && wc -l < "$SYSADMIN_KEYS" || echo "0")${RESET}"
    echo -e "Password configured: ${GREEN}$([ -f "$SERVER_HASH" ] && echo "✓" || echo "✗")${RESET}"
    echo -e "Telegram configured: ${GREEN}$([ -f "$TELEGRAM_CONFIG" ] && echo "✓" || echo "✗")${RESET}"
    echo -e "Service active: ${GREEN}$(systemctl is-active backup-system.service 2>/dev/null || echo "inactive")${RESET}"
    echo
}

show_help(){
    echo "Automatic Backup System - Network Administration"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "OPTIONS:"
    echo "  -m or --monitor              Start USB device monitor"
    echo "  -s or --setup                Initial system configuration"
    echo "  -k or --add-key <file>       Authorize sysadmin public key"
    echo "  -p or --set-password <pass>  Set the server password"
    echo "  -t or --status               Show system status"
    echo "  -h or --help                 Show this help"
    echo "EXAMPLES:"
    echo "  $0 --monitor                        # Start monitor"
    echo "  $0 --setup                          # Initial configuration"
    echo "  $0 --add-key /path/to/public.pem    # Authorize sysadmin"
    echo "  $0 --set-password "my_password"     # Configure password"
    echo "  $0 --status                         # Show system status"
    echo "  $0 --help                           # Show help"


    echo "CONFIGURATION FILES:"
    echo "  $SERVER_CONFIG      # Server configuration"
    echo "  $SYSADMIN_KEYS      # Authorized public keys"
    echo "  $SERVER_HASH        # Server password hash"
    echo "  $TELEGRAM_CONFIG    # Telegram configuration"
}

#===================#
# MAIN FUNCTION #
#===================#

main() {
    # Verify that it is running as root
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root"
    fi
    test "$1" == "-m" || test "$1" == "--monitor" && { check_dependencies; create_directories; monitor_usb; exit; }
    test "$1" == "-s" || test "$1" == "--setup" && { check_dependencies; setup_initial_config; exit; }
    test "$1" == "-k" || test "$1" == "--add-key" && { test -z "$2" && error_exit "You must specify the public key file"; add_sysadmin_key "$2"; exit; }
    test "$1" == "-p" || test "$1" == "--set-password" && {
        if [ -n "$2" ]; then
            warning_message "Passing passwords as command-line arguments exposes them to other processes"
            set_server_password "$2"
        else
            read -r -s -p "Server password: " password
            echo
            set_server_password "$password"
        fi
        exit
    }
    test "$1" == "-t" || test "$1" == "--status" && { show_status; exit; }
    test "$1" == "-h" || test "$1" == "--help" && { show_help; exit; }
    test -z "$1" && { show_help; exit; }
    error_exit "Invalid option: $1. Use -h or --help to see the available options."
}

main "$@"