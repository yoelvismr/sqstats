#!/bin/bash
set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
info() { echo -e "${BLUE}INFO: $1${NC}"; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }

APP_DIR="/opt/SquidStats"

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse con sudo"
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    error "Directorio de aplicación no encontrado: $APP_DIR"
    exit 1
fi

cd "$APP_DIR"

if [ ! -f "venv/bin/activate" ]; then
    error "Entorno virtual no encontrado"
    exit 1
fi

info "🔄 Actualizando SquidStats..."

# Cambiar al usuario de la aplicación para mantener permisos
sudo -u squidstats bash << EOF
source $APP_DIR/venv/bin/activate

if python3 utils/updateSquidStats.py; then
    echo -e "${GREEN}✅ SquidStats actualizado correctamente${NC}"
else
    echo -e "${RED}❌ Error actualizando SquidStats${NC}"
    exit 1
fi

deactivate
EOF

if [ $? -eq 0 ]; then
    success "Proceso de actualización completado"
else
    error "Error en el proceso de actualización"
    exit 1
fi