#!/bin/bash

#=====================================#
# SYSTEM KEY GENERATOR #
#=====================================#

source "${0%/*}"/messages.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

generate_sysadmin_keys() {
    local sysadmin_id="$1"
    local output_dir="${2:-./keys}"
    
    if [ -z "$sysadmin_id" ]; then
        error_exit "You must specify the sysadmin ID"
    fi
    
    mkdir -p "$output_dir"
    
    local private_key="$output_dir/${sysadmin_id}_private.pem"
    local public_key="$output_dir/${sysadmin_id}_public.pem"
    
    info_message "Generating key pair for sysadmin: $sysadmin_id"
    
    # Generate private key
    openssl genrsa -out "$private_key" 2048 || error_exit "Error generating private key"
    chmod 600 "$private_key"
    
    # Extract public key
    openssl rsa -in "$private_key" -pubout -out "$public_key" || error_exit "Error extracting public key"
    
    # Create the sysadmin ID file
    echo "$sysadmin_id" > "$output_dir/sysadmin_id.txt"
    
    success_message "Keys generated successfully:"
    echo "  - Private key: $private_key"
    echo "  - Public key: $public_key"
    echo "  - Sysadmin ID: $output_dir/sysadmin_id.txt"
    
    info_message "Copy $private_key and sysadmin_id.txt to the USB drive"
    info_message "Authorize $public_key on the server with: backup-system --add-key $public_key"
}

show_help() {
    echo "System Key Generator"
    echo ""
    echo "Usage: $0 <sysadmin_id>"
    echo "Example: $0 sysadmin123"
}

test "$1" == "-h" || test "$1" == "--help" && { show_help; exit; }
test -z "$1" && { show_help; exit; }

generate_sysadmin_keys "$1" "$2"