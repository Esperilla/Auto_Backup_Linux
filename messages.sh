#!/bin/bash

#==================================#
# SYSTEM MESSAGES SCRIPT #
#==================================#
LOG_DIR="/var/log/backup-system"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >&2
        return 1
    }
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/backup.log"
}

success_message() {
    log_message "INFO" "$1"
    echo -e "${GREEN}✓ $1${RESET}"
}

info_message() {
    log_message "INFO" "$1"
    echo -e "${BLUE}ℹ $1${RESET}"
}

error_exit() {
    log_message "ERROR" "$1"
    echo -e "${RED}ERROR: $1${RESET}" >&2
    exit 1
}

warning_message() {
    log_message "WARNING" "$1"
    echo -e "${YELLOW}⚠ $1${RESET}"
}