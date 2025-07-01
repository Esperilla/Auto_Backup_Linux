#!/bin/bash

#====================================================#
# EJECUCIÓN DEL SISTEMA DE RESPALDO EN SEGUNDO PLANO #
#====================================================#

DEVICE="$1"

# Ejecutar el sistema de respaldo en segundo plano
nohup /usr/local/bin/backup-system --process-usb "$DEVICE"
exit 0