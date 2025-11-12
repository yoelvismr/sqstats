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
SERVICE_USER="squidstats"

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse con sudo"
    exit 1
fi

info "🔧 Reparando permisos..."

# Reparar permisos de Squid
chown -R proxy:proxy /var/log/squid 2>/dev/null || true
chown proxy:proxy /var/spool/squid 2>/dev/null || true
chmod 755 /var/log/squid 2>/dev/null || true
chmod 755 /var/spool/squid 2>/dev/null || true
find /var/log/squid -type f -name "*.log" -exec chmod 644 {} \; 2>/dev/null || true

# Reparar permisos de aplicación
chown -R "$SERVICE_USER":"$SERVICE_USER" "$APP_DIR" 2>/dev/null || true
chown -R "$SERVICE_USER":"$SERVICE_USER" /var/log/squidstats 2>/dev/null || true
chown -R "$SERVICE_USER":"$SERVICE_USER" /var/run/squidstats 2>/dev/null || true
chmod 750 "$APP_DIR" 2>/dev/null || true
chmod 755 /var/log/squidstats 2>/dev/null || true
chmod 755 /var/run/squidstats 2>/dev/null || true

# Asegurar permisos de scripts de mantenimiento
if [ -d "$APP_DIR/maintenance" ]; then
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$APP_DIR/maintenance"
    find "$APP_DIR/maintenance" -name "*.sh" -exec chmod 700 {} \; 2>/dev/null || true
fi

success "✅ Permisos reparados correctamente"