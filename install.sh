#!/bin/bash

set -e  # Salir ante cualquier error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuración
APP_NAME="SquidStats"
REPO_URL="https://github.com/yoelvismr/sqstats.git"
DEFAULT_PROD_DIR="/opt/SquidStats"
DEVELOPMENT_DIR=$(pwd)

# Variables globales
INSTALL_MODE=""
APP_DIR=""
VENV_DIR=""
SERVICE_USER=""
IS_UPDATE=false
IS_UNINSTALL=false

# =====================================================================
# FUNCIONES DE UTILIDAD
# =====================================================================

function error() { echo -e "\n${RED}ERROR: $1${NC}\n" >&2; }
function warning() { echo -e "\n${YELLOW}WARNING: $1${NC}\n"; }
function info() { echo -e "\n${BLUE}INFO: $1${NC}\n"; }
function success() { echo -e "\n${GREEN}SUCCESS: $1${NC}\n"; }
function step() { echo -e "\n${PURPLE}>>> $1${NC}"; }

function ask_yes_no() {
    local prompt="$1" default="${2:-y}" answer options
    
    if [ "$default" = "y" ]; then options="[Y/n]"; else options="[y/N]"; fi
    
    while true; do
        read -p "$prompt $options: " answer
        case "${answer:-$default}" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo -e "${YELLOW}Por favor responde yes (y) o no (n).${NC}" ;;
        esac
    done
}

# =====================================================================
# FUNCIONES DEL SISTEMA
# =====================================================================

function check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        error "Este script debe ejecutarse con privilegios de superusuario"
        exit 1
    fi
}

function check_systemd() {
    if command -v systemctl >/dev/null 2>&1 && \
       systemctl --version >/dev/null 2>&1 && \
       [ -d /run/systemd/system ]; then
        return 0
    else
        warning "⚠️ systemd no disponible - los servicios no se gestionarán automáticamente"
        return 1
    fi
}

function check_environment() {
    step "Verificando entorno del sistema"
    info "Arquitectura: $(uname -m)"
    if command -v lsb_release >/dev/null 2>&1; then
        info "Sistema: $(lsb_release -d | cut -f2)"
    elif [ -f /etc/os-release ]; then
        info "Sistema: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    fi
    check_systemd > /dev/null
}

function is_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

function is_service_available() {
    command -v "$1" &> /dev/null
}

function is_service_running() {
    local service_name=$1
    if check_systemd; then
        systemctl is-active --quiet "$service_name" 2>/dev/null
        return $?
    else
        pgrep -x "$service_name" >/dev/null 2>&1
        return $?
    fi
}

# =====================================================================
# FUNCIONES PRINCIPALES DE INSTALACIÓN
# =====================================================================

function detect_install_mode() {
    if [ -f "$DEFAULT_PROD_DIR/.env" ] || (check_systemd && systemctl is-active --quiet squidstats 2>/dev/null); then
        INSTALL_MODE="production"
        APP_DIR="$DEFAULT_PROD_DIR"
        info "✅ Instalación de producción detectada en: $APP_DIR"
        if ask_yes_no "¿Desea actualizar la instalación existente?" "y"; then
            IS_UPDATE=true
        else
            info "Operación cancelada por el usuario"
            exit 0
        fi
    elif [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -f "$DEVELOPMENT_DIR/.env" ]; then
        INSTALL_MODE="development"
        if [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -d "$DEVELOPMENT_DIR/SquidStats/.git" ]; then
            APP_DIR="$DEVELOPMENT_DIR/SquidStats"
        else
            APP_DIR="$DEVELOPMENT_DIR"
        fi
        info "✅ Instalación de desarrollo detectada en: $APP_DIR"
        if ask_yes_no "¿Desea actualizar la instalación existente?" "y"; then
            IS_UPDATE=true
        else
            info "Operación cancelada por el usuario"
            exit 0
        fi
    else
        echo -e "${CYAN}=== MODO DE INSTALACIÓN SQUIDSTATS ===${NC}"
        echo "1) 🛠️  Desarrollo - Para testing y desarrollo local"
        echo "   • Directorio: $(pwd)/SquidStats"
        echo "   • SQLite database"
        echo "   • Servidor Flask integrado"
        echo "   • Sin servicios systemd"
        echo ""
        echo "2) 🚀 Producción - Para servidores dedicados"
        echo "   • Directorio /opt/SquidStats"
        echo "   • Base de datos MariaDB/PostgreSQL"
        echo "   • Nginx + Gunicorn"
        echo "   • Servicios systemd"
        echo ""
        echo "3) ❌ Cancelar instalación"
        echo ""
        
        while true; do
            read -p "Seleccione el modo de instalación [1/2/3]: " choice
            case $choice in
                1) 
                    INSTALL_MODE="development"
                    APP_DIR="$DEVELOPMENT_DIR/SquidStats"
                    info "Modo desarrollo seleccionado"
                    break
                    ;;
                2) 
                    INSTALL_MODE="production"
                    APP_DIR="$DEFAULT_PROD_DIR"
                    if [ "$EUID" -ne 0 ]; then
                        error "El modo producción requiere privilegios de superusuario"
                        if ask_yes_no "¿Cambiar a modo desarrollo?" "y"; then
                            INSTALL_MODE="development"
                            APP_DIR="$DEVELOPMENT_DIR/SquidStats"
                            info "Modo desarrollo seleccionado"
                        else
                            exit 0
                        fi
                    else
                        check_sudo
                        info "Modo producción seleccionado"
                    fi
                    break
                    ;;
                3) exit 0 ;;
                *) error "Opción inválida. Por favor ingrese 1, 2 o 3." ;;
            esac
        done
    fi
}

function check_and_install_squid() {
    step "Verificando Squid Proxy"
    
    if is_service_available "squid"; then
        if is_service_running "squid"; then
            success "✅ Squid está instalado y ejecutándose correctamente"
            return 0
        else
            info "⚠️ Squid está instalado pero no está ejecutándose"
            if check_systemd && ask_yes_no "¿Desea iniciar el servicio Squid?" "y"; then
                systemctl start squid && success "Squid iniciado correctamente" && return 0
            fi
            return 1
        fi
    else
        warning "Squid Proxy no está instalado en el sistema."
        echo -e "${YELLOW}Squid es necesario para que SquidStats funcione correctamente.${NC}"
        
        if ask_yes_no "¿Desea instalar y configurar Squid Proxy ahora?" "y"; then
            info "Instalando Squid..."
            apt-get update && apt-get install -y squid && success "Squid instalado correctamente"
            
            local squid_conf="/etc/squid/squid.conf"
            if [ -f "$squid_conf" ]; then
                cp "$squid_conf" "$squid_conf.backup.$(date +%Y%m%d_%H%M%S)"
                cat > "$squid_conf" << 'EOF'
# Squid Configuration for SquidStats
http_port 3128
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 21
acl Safe_ports port 1025-65535
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localnet
http_access allow localhost
http_access deny all
logformat squidstats %ts.%03tu %6tr %>a %Ss/%03>Hs %<st %rm %ru %un %Sh/%<A %mt
access_log /var/log/squid/access.log squidstats
cache deny all
visible_hostname squidstats
EOF
                mkdir -p /var/log/squid
                chown -R proxy:proxy /var/log/squid
                chmod 755 /var/log/squid
                mkdir -p /var/spool/squid
                chown proxy:proxy /var/spool/squid
                
                if squid -k parse 2>/dev/null; then
                    squid -z 2>/dev/null || true
                    systemctl enable squid
                    systemctl start squid
                    success "Squid configurado e iniciado correctamente"
                    return 0
                fi
            fi
        else
            warning "Squid no se instalará. SquidStats necesitará que configure Squid manualmente."
            return 1
        fi
    fi
}

function install_system_dependencies() {
    step "Verificando dependencias del sistema"
    
    local base_packages=("git" "python3" "python3-pip" "python3-venv" "curl")
    local missing_packages=()
    
    for pkg in "${base_packages[@]}"; do
        if ! is_package_installed "$pkg" && ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        success "✅ Todas las dependencias del sistema ya están instaladas"
        return 0
    fi
    
    info "Se necesitan instalar las siguientes dependencias: ${missing_packages[*]}"
    apt-get update && apt-get install -y "${missing_packages[@]}" && success "Dependencias del sistema instaladas correctamente"
}

function setup_application_user() {
    if [ "$INSTALL_MODE" != "production" ]; then return 0; fi
    
    step "Configurando usuario de aplicación"
    
    if ! id "squidstats" &>/dev/null; then
        useradd -r -s /bin/false -d "$APP_DIR" -c "SquidStats Application" squidstats && info "Usuario squidstats creado"
    else
        info "Usuario squidstats ya existe"
    fi
    
    mkdir -p /var/log/squidstats /var/run/squidstats
    chown squidstats:squidstats /var/log/squidstats /var/run/squidstats
    chmod 755 /var/log/squidstats /var/run/squidstats
    SERVICE_USER="squidstats"
    success "Usuario y directorios de aplicación configurados"
}

function clone_or_update_repository() {
    step "Obteniendo código de la aplicación"
    
    if [ "$IS_UPDATE" = true ] && [ -d "$APP_DIR/.git" ]; then
        info "🔄 Actualizando repositorio existente..."
        cd "$APP_DIR"
        
        if [ -f ".env" ]; then
            cp .env "/tmp/squidstats_env_backup_$(date +%Y%m%d_%H%M%S)"
            info "Configuración .env respaldada"
        fi
        
        if compgen -G "*.db" > /dev/null; then
            mkdir -p "/tmp/squidstats_db_backup_$(date +%Y%m%d_%H%M%S)"
            cp *.db "/tmp/squidstats_db_backup_$(date +%Y%m%d_%H%M%S)/" 2>/dev/null || true
            info "Base de datos respaldada"
        fi
        
        git stash push -m "Auto-stash by installer $(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        if git fetch origin && git reset --hard origin/main; then
            local latest_env_backup=$(ls -t /tmp/squidstats_env_backup_* 2>/dev/null | head -1)
            if [ -n "$latest_env_backup" ] && [ -f "$latest_env_backup" ]; then
                cp "$latest_env_backup" .env
                rm -f "$latest_env_backup"
                info "Configuración .env restaurada desde backup"
            fi
            
            local latest_db_backup=$(ls -dt /tmp/squidstats_db_backup_* 2>/dev/null | head -1)
            if [ -n "$latest_db_backup" ] && [ -d "$latest_db_backup" ]; then
                cp "$latest_db_backup"/*.db . 2>/dev/null || true
                rm -rf "$latest_db_backup"
                info "Base de datos restaurada desde backup"
            fi
            
            if git stash list | grep -q "Auto-stash by installer"; then
                if ask_yes_no "Se encontraron cambios locales. ¿Desea intentar aplicarlos?" "n"; then
                    git stash pop 2>/dev/null || warning "Conflicto al aplicar cambios locales. Resuelva manualmente."
                else
                    git stash drop 2>/dev/null || true
                fi
            fi
            
            success "Repositorio actualizado correctamente"
        else
            error "Error al actualizar el repositorio"
            return 1
        fi
    elif [ -d "$APP_DIR/.git" ]; then
        info "✅ Repositorio Git ya existe"
        return 0
    elif [ ! -d "$APP_DIR" ]; then
        info "Clonando repositorio desde $REPO_URL..."
        git clone "$REPO_URL" "$APP_DIR" && success "Repositorio clonado correctamente en $APP_DIR"
    else
        warning "El directorio $APP_DIR ya existe pero no es un repositorio git"
        echo -e "${YELLOW}Opciones disponibles:${NC}"
        echo "1) Usar el directorio existente"
        echo "2) Hacer backup y clonar repositorio fresco"
        echo "3) Cancelar instalación"
        
        while true; do
            read -p "Seleccione opción [1/2/3]: " choice
            case $choice in
                1) info "Usando directorio existente $APP_DIR"; return 0 ;;
                2)
                    local backup_dir="${APP_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                    mv "$APP_DIR" "$backup_dir" && git clone "$REPO_URL" "$APP_DIR" && \
                    success "Repositorio clonado correctamente" && info "Backup disponible en: $backup_dir" && return 0
                    ;;
                3) exit 0 ;;
                *) error "Opción inválida. Por favor ingrese 1, 2 o 3." ;;
            esac
        done
    fi
}

function setup_python_environment() {
    step "Configurando entorno Python"
    
    VENV_DIR="$APP_DIR/venv"
    
    if [ ! -d "$APP_DIR" ]; then
        error "El directorio de la aplicación no existe: $APP_DIR"
        return 1
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR" && success "Entorno virtual creado en $VENV_DIR"
        NEW_VENV=true
    else
        [ "$IS_UPDATE" = true ] && info "🔄 Actualizando dependencias..." || info "✅ Entorno virtual ya existe"
        NEW_VENV=false
    fi
    
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    
    local requirements_path="$APP_DIR/requirements.txt"
    if [ ! -f "$requirements_path" ]; then
        error "Archivo requirements.txt no encontrado en $APP_DIR"
        deactivate
        return 1
    fi
    
    if [ "$NEW_VENV" = true ] || [ "$IS_UPDATE" = true ]; then
        if pip install --no-cache-dir -r "$requirements_path"; then
            [ "$IS_UPDATE" = true ] && success "Dependencias actualizadas correctamente" || success "Dependencias instaladas correctamente"
        else
            error "Error al instalar dependencias"
            pip install flask sqlalchemy requests && success "Dependencias básicas instaladas" || error "No se pudieron instalar las dependencias básicas"
        fi
    else
        info "✅ Dependencias ya instaladas"
    fi
    
    deactivate
}

function configure_database() {
    step "Configurando base de datos"
    
    local env_file="$APP_DIR/.env"
    
    if [ "$INSTALL_MODE" = "development" ]; then
        local db_path="$APP_DIR/squidstats.db"
        cat >> "$env_file" << EOF

# Database Configuration - Development
DATABASE_TYPE=SQLITE
DATABASE_STRING_CONNECTION=$db_path
EOF
        success "Base de datos SQLite configurada: $db_path"
        return 0
    fi
    
    echo -e "${CYAN}=== CONFIGURACIÓN DE BASE DE DATOS PARA PRODUCCIÓN ===${NC}"
    echo "1) SQLite (Recomendado para pruebas/entornos pequeños)"
    echo "2) MariaDB/MySQL (Recomendado para producción)"
    echo "3) PostgreSQL (Recomendado para alta performance)"
    
    while true; do
        read -p "Seleccione [1/2/3]: " db_choice
        case $db_choice in
            1) configure_sqlite "$env_file"; break ;;
            2) configure_mariadb "$env_file"; break ;;
            3) configure_postgresql "$env_file"; break ;;
            *) error "Opción inválida. Intente nuevamente." ;;
        esac
    done
}

function configure_sqlite() {
    local env_file="$1" db_path="$APP_DIR/squidstats.db"
    cat >> "$env_file" << EOF

# Database Configuration - SQLite
DATABASE_TYPE=SQLITE
DATABASE_STRING_CONNECTION=$db_path
EOF
    success "Base de datos SQLite configurada: $db_path"
}

function check_and_install_mariadb() {
    info "Verificando MariaDB/MySQL..."
    
    # Verificar si MariaDB/MySQL está instalado
    if is_service_available "mysql" || is_service_available "mariadb"; then
        # Verificar si el servicio está corriendo
        if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
            success "✅ MariaDB/MySQL está instalado y ejecutándose"
            return 0
        else
            info "⚠️ MariaDB/MySQL está instalado pero no está ejecutándose"
            if ask_yes_no "¿Desea iniciar el servicio de base de datos?" "y"; then
                systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
                if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
                    success "Servicio de base de datos iniciado correctamente"
                    return 0
                else
                    error "No se pudo iniciar el servicio de base de datos"
                    return 1
                fi
            else
                warning "El servicio de base de datos no está ejecutándose"
                return 1
            fi
        fi
    else
        # MariaDB/MySQL no está instalado
        warning "MariaDB/MySQL no está instalado en el sistema."
        echo -e "${YELLOW}Se requiere un servidor de base de datos para el modo producción.${NC}"
        
        if ask_yes_no "¿Desea instalar MariaDB ahora?" "y"; then
            info "Instalando MariaDB server..."
            if apt-get install -y mariadb-server; then
                success "MariaDB instalado correctamente"
                # Iniciar y habilitar servicio
                systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
                systemctl enable mariadb 2>/dev/null || systemctl enable mysql 2>/dev/null
                return 0
            else
                error "Error al instalar MariaDB"
                return 1
            fi
        else
            warning "MariaDB/MySQL no se instalará. Debe configurar manualmente un servidor de base de datos."
            info "Para instalar MariaDB/MySQL manualmente:"
            echo -e "  ${CYAN}sudo apt-get install mariadb-server${NC}"
            echo -e "  ${CYAN}sudo mysql_secure_installation${NC}"
            return 1
        fi
    fi
}

function configure_mariadb() {
    local env_file="$1"
    
    # Verificar e instalar MariaDB si es necesario
    if ! check_and_install_mariadb; then
        error "No se puede continuar sin MariaDB/MySQL"
        return 1
    fi
    
    # Get database credentials
    echo -e "${YELLOW}--- Configuración de MariaDB/MySQL ---${NC}"
    read -p "Nombre de la base de datos [squidstats]: " db_name
    db_name=${db_name:-squidstats}
    
    read -p "Usuario de la base de datos [squidstats_user]: " db_user
    db_user=${db_user:-squidstats_user}
    
    while true; do
        read -s -p "Contraseña para el usuario: " db_pass
        echo
        if [ -z "$db_pass" ]; then
            error "La contraseña no puede estar vacía"
            continue
        fi
        read -s -p "Confirme la contraseña: " db_pass_confirm
        echo
        if [ "$db_pass" != "$db_pass_confirm" ]; then
            error "Las contraseñas no coinciden"
        else
            break
        fi
    done
    
    read -p "Host de la base de datos [localhost]: " db_host
    db_host=${db_host:-localhost}
    
    read -p "Puerto de la base de datos [3306]: " db_port
    db_port=${db_port:-3306}
    
    # Create database and user
    info "Creando base de datos y usuario..."
    
    # Try to connect without password first, then with password
    local mysql_root_cmd="mysql -u root"
    if ! $mysql_root_cmd -e "SELECT 1" &>/dev/null; then
        # Try with sudo
        mysql_root_cmd="sudo mysql -u root"
        if ! $mysql_root_cmd -e "SELECT 1" &>/dev/null; then
            error "No se puede conectar a MySQL como root. Configure manualmente la base de datos."
            info "Puede necesitar configurar la autenticación root:"
            echo -e "  ${CYAN}sudo mysql_secure_installation${NC}"
            echo -e "  ${CYAN}sudo mysql -u root -p${NC}"
            return 1
        fi
    fi
    
    # Execute SQL commands
    $mysql_root_cmd << EOF
CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'$db_host' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'$db_host';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        local conn_string="mysql+pymysql://$db_user:$db_pass@$db_host:$db_port/$db_name"
        cat >> "$env_file" << EOF

# Database Configuration - MariaDB
DATABASE_TYPE=MARIADB
DATABASE_STRING_CONNECTION=$conn_string
EOF
        success "Base de datos MariaDB configurada correctamente"
        info "Base de datos: $db_name, Usuario: $db_user, Host: $db_host:$db_port"
    else
        error "Error al configurar MariaDB"
        return 1
    fi
}

function check_and_install_postgresql() {
    info "Verificando PostgreSQL..."
    
    # Verificar si PostgreSQL está instalado
    if is_service_available "psql"; then
        # Verificar si el servicio está corriendo
        if systemctl is-active --quiet postgresql 2>/dev/null; then
            success "✅ PostgreSQL está instalado y ejecutándose"
            return 0
        else
            info "⚠️ PostgreSQL está instalado pero no está ejecutándose"
            if ask_yes_no "¿Desea iniciar el servicio PostgreSQL?" "y"; then
                systemctl start postgresql
                if systemctl is-active --quiet postgresql; then
                    success "Servicio PostgreSQL iniciado correctamente"
                    return 0
                else
                    error "No se pudo iniciar el servicio PostgreSQL"
                    return 1
                fi
            else
                warning "El servicio PostgreSQL no está ejecutándose"
                return 1
            fi
        fi
    else
        # PostgreSQL no está instalado
        warning "PostgreSQL no está instalado en el sistema."
        echo -e "${YELLOW}Se requiere un servidor de base de datos para el modo producción.${NC}"
        
        if ask_yes_no "¿Desea instalar PostgreSQL ahora?" "y"; then
            info "Instalando PostgreSQL..."
            if apt-get install -y postgresql postgresql-contrib; then
                success "PostgreSQL instalado correctamente"
                # Iniciar y habilitar servicio
                systemctl start postgresql
                systemctl enable postgresql
                return 0
            else
                error "Error al instalar PostgreSQL"
                return 1
            fi
        else
            warning "PostgreSQL no se instalará. Debe configurar manualmente un servidor de base de datos."
            info "Para instalar PostgreSQL manualmente:"
            echo -e "  ${CYAN}sudo apt-get install postgresql postgresql-contrib${NC}"
            return 1
        fi
    fi
}

function configure_postgresql() {
    local env_file="$1"
    
    # Verificar e instalar PostgreSQL si es necesario
    if ! check_and_install_postgresql; then
        error "No se puede continuar sin PostgreSQL"
        return 1
    fi
    
    # Get database credentials
    echo -e "${YELLOW}--- Configuración de PostgreSQL ---${NC}"
    read -p "Nombre de la base de datos [squidstats]: " db_name
    db_name=${db_name:-squidstats}
    
    read -p "Usuario de la base de datos [squidstats_user]: " db_user
    db_user=${db_user:-squidstats_user}
    
    while true; do
        read -s -p "Contraseña para el usuario: " db_pass
        echo
        if [ -z "$db_pass" ]; then
            error "La contraseña no puede estar vacía"
            continue
        fi
        read -s -p "Confirme la contraseña: " db_pass_confirm
        echo
        if [ "$db_pass" != "$db_pass_confirm" ]; then
            error "Las contraseñas no coinciden"
        else
            break
        fi
    done
    
    read -p "Host de la base de datos [localhost]: " db_host
    db_host=${db_host:-localhost}
    
    read -p "Puerto de la base de datos [5432]: " db_port
    db_port=${db_port:-5432}
    
    # Create database and user as postgres user
    info "Creando base de datos y usuario..."
    
    sudo -u postgres psql << EOF
CREATE USER $db_user WITH PASSWORD '$db_pass';
CREATE DATABASE $db_name OWNER $db_user;
GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;
\c $db_name;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOF
    
    if [ $? -eq 0 ]; then
        local conn_string="postgresql+psycopg2://$db_user:$db_pass@$db_host:$db_port/$db_name"
        cat >> "$env_file" << EOF

# Database Configuration - PostgreSQL
DATABASE_TYPE=POSTGRESQL
DATABASE_STRING_CONNECTION=$conn_string
EOF
        success "Base de datos PostgreSQL configurada correctamente"
        info "Base de datos: $db_name, Usuario: $db_user, Host: $db_host:$db_port"
    else
        error "Error al configurar PostgreSQL"
        return 1
    fi
}

function create_environment_file() {
    step "Configurando variables de entorno"
    
    local env_file="$APP_DIR/.env"
    
    if [ -f "$env_file" ] && [ "$IS_UPDATE" = true ]; then
        info "✅ Archivo .env ya existe, conservando configuración existente"
        if ! grep -q "VERSION=" "$env_file"; then
            echo -e "\n# SquidStats Configuration - Updated $(date)" >> "$env_file"
            echo "VERSION=2" >> "$env_file"
        fi
        return 0
    elif [ -f "$env_file" ]; then
        if ask_yes_no "El archivo .env ya existe. ¿Desea sobrescribirlo?" "n"; then
            mv "$env_file" "$env_file.backup.$(date +%Y%m%d_%H%M%S)"
            info "Backup creado: $env_file.backup.*"
        else
            info "Conservando archivo .env existente"
            return 0
        fi
    fi
    
    cat > "$env_file" << EOF
# SquidStats Configuration - Generated $(date)
VERSION=2

# Application Mode
FLASK_DEBUG=$([ "$INSTALL_MODE" = "development" ] && echo "True" || echo "False")
LOG_LEVEL=$([ "$INSTALL_MODE" = "development" ] && echo "DEBUG" || echo "INFO")

# Security
SECRET_KEY=$(openssl rand -hex 32)

# Squid Configuration
SQUID_LOG=/var/log/squid/access.log
SQUID_HOST=127.0.0.1
SQUID_PORT=3128
LOG_FORMAT=DETAILED

# Application Settings
REFRESH_INTERVAL=60
BLACKLIST_DOMAINS="facebook.com,twitter.com,instagram.com,tiktok.com,youtube.com"

# Paths
SQUID_CONFIG_PATH=/etc/squid/squid.conf
ACL_FILES_DIR=/etc/squid/conf.d

# Network
LISTEN_HOST=127.0.0.1
LISTEN_PORT=5000
EOF
    
    if [ "$INSTALL_MODE" = "production" ] && [ -n "$SERVICE_USER" ]; then
        chown "$SERVICE_USER":"$SERVICE_USER" "$env_file"
    fi
    chmod 600 "$env_file"
    success "Archivo de configuración creado: $env_file"
}

function setup_squid_permissions() {
    step "Configurando permisos de Squid"
    
    if ! getent group proxy >/dev/null 2>&1; then
        warning "Grupo 'proxy' no encontrado. Squid puede no estar instalado correctamente."
        return 1
    fi
    
    local target_user=""
    if [ "$INSTALL_MODE" = "production" ]; then
        if [ -n "$SERVICE_USER" ] && id "$SERVICE_USER" >/dev/null 2>&1; then
            target_user="$SERVICE_USER"
            info "Configurando permisos para usuario de producción: $target_user"
        else
            error "Usuario de servicio '$SERVICE_USER' no encontrado."
            return 1
        fi
    else
        target_user="${SUDO_USER:-$USER}"
        info "Configurando permisos para usuario de desarrollo: $target_user"
    fi
    
    if ! id "$target_user" >/dev/null 2>&1; then
        error "Usuario '$target_user' no encontrado"
        return 1
    fi
    
    if ! groups "$target_user" | grep -q "\bproxy\b"; then
        info "Agregando usuario '$target_user' al grupo 'proxy'..."
        usermod -a -G proxy "$target_user" && success "Usuario '$target_user' agregado al grupo 'proxy'"
    else
        info "✅ El usuario '$target_user' ya pertenece al grupo 'proxy'"
    fi
    
    local squid_log_dir="/var/log/squid"
    if [ -d "$squid_log_dir" ]; then
        chmod 755 "$squid_log_dir"
        chown proxy:proxy "$squid_log_dir"
        find "$squid_log_dir" -type f -name "*.log" -exec chmod 644 {} \; 2>/dev/null || true
        success "Permisos del directorio de logs configurados"
    else
        warning "Directorio de logs de Squid no encontrado: $squid_log_dir"
    fi
    
    local test_log="/var/log/squid/access.log"
    if [ -f "$test_log" ]; then
        if [ "$INSTALL_MODE" = "production" ]; then
            sudo -u "$target_user" test -r "$test_log" && success "✅ El usuario '$target_user' puede leer los logs de Squid" || \
            { warning "El usuario '$target_user' no puede leer los logs de Squid"; chmod 644 "$test_log" 2>/dev/null || true; }
        else
            test -r "$test_log" && success "✅ El usuario '$target_user' puede leer los logs de Squid" || \
            { warning "El usuario '$target_user' no puede leer los logs de Squid - puede necesitar cerrar y abrir sesión"; chmod 644 "$test_log" 2>/dev/null || true; }
        fi
    else
        info "Archivo de log de Squid no encontrado, se creará con los permisos correctos"
    fi
    
    success "Permisos de Squid configurados correctamente"
}

function restart_squid_service() {
    if systemctl is-active --quiet squid; then
        info "Reiniciando servicio Squid para aplicar cambios..."
        systemctl restart squid && success "Servicio Squid reiniciado correctamente" || error "Error al reiniciar servicio Squid"
    else
        info "Servicio Squid no está ejecutándose"
    fi
}

function setup_nginx() {
    if [ "$INSTALL_MODE" != "production" ]; then return 0; fi
    
    step "Configurando Nginx"
    
    if ! is_service_available "nginx"; then
        warning "Nginx no está instalado."
        if ask_yes_no "¿Desea instalar Nginx ahora?" "y"; then
            apt-get install -y nginx && systemctl enable nginx && systemctl start nginx && success "Nginx instalado correctamente"
        else
            error "No se puede continuar sin Nginx"
            return 1
        fi
    fi
    
    local nginx_conf="/etc/nginx/sites-available/squidstats"
    cat > "$nginx_conf" << EOF
server {
    listen 80;
    server_name _;
    
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    client_max_body_size 10M;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location /static/ {
        alias $APP_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    location ~ /\. { deny all; access_log off; log_not_found off; }
    location ~* \.(env|log|sql|db)$ { deny all; access_log off; log_not_found off; }
}
EOF
    
    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"
    rm -f /etc/nginx/sites-enabled/default
    
    if nginx -t; then
        systemctl reload nginx
        success "Nginx configurado correctamente"
    else
        error "Error en la configuración de Nginx"
        return 1
    fi
}

function setup_systemd_service() {
    if [ "$INSTALL_MODE" != "production" ]; then return 0; fi
    
    if ! check_systemd; then
        warning "systemd no disponible - omitiendo configuración de servicio"
        return 0
    fi
    
    step "Configurando servicio Systemd"
    
    local service_file="/etc/systemd/system/squidstats.service"
    
    # Verificar que los archivos necesarios existen
    if [ ! -f "$APP_DIR/wsgi.py" ]; then
        error "Archivo wsgi.py no encontrado en $APP_DIR"
        return 1
    fi
    
    if [ ! -f "$APP_DIR/gunicorn.conf.py" ]; then
        error "Archivo gunicorn.conf.py no encontrado en $APP_DIR"
        return 1
    fi
    
    if [ ! -f "$VENV_DIR/bin/gunicorn" ]; then
        error "Gunicorn no está instalado en el entorno virtual"
        return 1
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=SquidStats Web Application
Documentation=https://github.com/kaelthasmanu/SquidStats
After=network.target nginx.service squid.service
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin
Environment=PYTHONPATH=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$VENV_DIR/bin/gunicorn -c $APP_DIR/gunicorn.conf.py wsgi:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

; Timeout para inicio
TimeoutStartSec=30
TimeoutStopSec=30

; Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$APP_DIR /var/log/squidstats /var/run/squidstats
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

; Resource limits
MemoryLimit=512M
CPUQuota=100%
LimitNOFILE=65536

; Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=squidstats

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable squidstats.service
    
    if [ "$IS_UPDATE" = false ]; then
        info "Iniciando servicio squidstats..."
        if systemctl start squidstats.service; then
            # Esperar un poco más y verificar el estado
            sleep 5
            if systemctl is-active --quiet squidstats.service; then
                success "Servicio Systemd configurado e iniciado"
                
                # Mostrar logs recientes para diagnóstico
                info "Mostrando logs del servicio (últimas 10 líneas):"
                journalctl -u squidstats.service -n 10 --no-pager
            else
                error "Error al iniciar el servicio Systemd"
                info "Mostrando logs detallados del servicio:"
                journalctl -u squidstats.service -n 20 --no-pager
                systemctl status squidstats.service
                return 1
            fi
        else
            error "No se pudo iniciar el servicio Systemd"
            info "Mostrando logs del servicio:"
            journalctl -u squidstats.service -n 20 --no-pager
            systemctl status squidstats.service
            return 1
        fi
    else
        info "Reiniciando servicio squidstats..."
        if systemctl restart squidstats.service; then
            sleep 5
            if systemctl is-active --quiet squidstats.service; then
                success "Servicio Systemd actualizado y reiniciado"
                
                # Mostrar logs recientes
                info "Mostrando logs del servicio (últimas 10 líneas):"
                journalctl -u squidstats.service -n 10 --no-pager
            else
                error "Error al reiniciar el servicio Systemd"
                info "Mostrando logs detallados del servicio:"
                journalctl -u squidstats.service -n 20 --no-pager
                systemctl status squidstats.service
                return 1
            fi
        else
            error "Error al reiniciar el servicio Systemd"
            info "Mostrando logs del servicio:"
            journalctl -u squidstats.service -n 20 --no-pager
            systemctl status squidstats.service
            return 1
        fi
    fi
}

function setup_logging() {
    if [ "$INSTALL_MODE" != "production" ]; then return 0; fi
    
    step "Configurando sistema de logs"
    
    local logrotate_conf="/etc/logrotate.d/squidstats"
    cat > "$logrotate_conf" << EOF
/var/log/squidstats/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su $SERVICE_USER $SERVICE_USER
    postrotate
        systemctl reload squidstats.service > /dev/null 2>/dev/null || true
    endscript
}
EOF
    
    mkdir -p /var/log/squidstats
    chown -R "$SERVICE_USER":"$SERVICE_USER" /var/log/squidstats
    chmod 755 /var/log/squidstats
    success "Sistema de logs configurado (rotación cada 30 días)"
}

function set_permissions() {
    step "Estableciendo permisos"
    
    if [ "$INSTALL_MODE" = "production" ]; then
        chown -R "$SERVICE_USER":"$SERVICE_USER" "$APP_DIR"
        chmod 750 "$APP_DIR"
        find "$APP_DIR" -type f -name "*.py" -exec chmod 644 {} \;
        find "$APP_DIR" -type f -name "*.sh" -exec chmod 700 {} \;
        find "$APP_DIR" -type f -name ".env" -exec chmod 600 {} \;
        chmod 755 "$APP_DIR/venv/bin/python3"
        success "Permisos de producción establecidos"
    else
        find "$APP_DIR" -type f -name "*.sh" -exec chmod 700 {} \;
        find "$APP_DIR" -type f -name ".env" -exec chmod 600 {} \;
        chmod 755 "$APP_DIR/venv/bin/python3"
        if [ -n "$SUDO_USER" ]; then
            chown -R "$SUDO_USER":"$SUDO_USER" "$APP_DIR" 2>/dev/null || true
        fi
        success "Permisos de desarrollo establecidos"
    fi
}

function finalize_installation() {
    step "Finalizando instalación"
    
    cd "$APP_DIR"
    source "$VENV_DIR/bin/activate"
    
    if python3 -c "from app import create_app; app, scheduler = create_app(); print('✅ Base de datos inicializada correctamente')"; then
        success "Base de datos inicializada"
    else
        error "Error al inicializar la base de datos"
        return 1
    fi
    
    deactivate
    
    echo -e "\n${GREEN}=== CONFIGURACIÓN DE PERMISOS SQUID ===${NC}"
    if [ "$INSTALL_MODE" = "production" ]; then
        echo -e "👤 Usuario del servicio: ${CYAN}$SERVICE_USER${NC}"
        echo -e "📊 Grupo proxy: ${CYAN}proxy${NC}"
        echo -e "✅ El usuario ${CYAN}$SERVICE_USER${NC} ha sido agregado al grupo ${CYAN}proxy${NC}"
    else
        local current_user="${SUDO_USER:-$USER}"
        echo -e "👤 Usuario de desarrollo: ${CYAN}$current_user${NC}"
        echo -e "📊 Grupo proxy: ${CYAN}proxy${NC}"
        echo -e "✅ El usuario ${CYAN}$current_user${NC} ha sido agregado al grupo ${CYAN}proxy${NC}"
        echo -e "\n${YELLOW}⚠️  NOTA:${NC} Para que los cambios de grupo surtan efecto, necesitas cerrar sesión y volver a entrar o ejecutar: ${CYAN}newgrp proxy${NC}"
    fi
    
    success "🎉 Instalación completada exitosamente!"
    
    echo -e "\n${GREEN}=== RESUMEN DE INSTALACIÓN ===${NC}"
    echo -e "📦 Modo: ${CYAN}$INSTALL_MODE${NC}"
    echo -e "📁 Directorio: ${CYAN}$APP_DIR${NC}"
    echo -e "🐍 Entorno virtual: ${CYAN}$VENV_DIR${NC}"
    
    if [ "$INSTALL_MODE" = "development" ]; then
        echo -e "\n🚀 ${YELLOW}PARA INICIAR LA APLICACIÓN EN MODO DESARROLLO:${NC}"
        echo -e "  ${CYAN}cd $APP_DIR${NC}"
        echo -e "  ${CYAN}source venv/bin/activate${NC}"
        echo -e "  ${CYAN}python3 app.py${NC}"
        echo -e "\n🌐 La aplicación estará disponible en: ${CYAN}http://127.0.0.1:5000${NC}"
    else
        echo -e "\n🔧 ${YELLOW}SERVICIOS CONFIGURADOS:${NC}"
        echo -e "  - ${CYAN}Nginx${NC} (proxy reverso)"
        echo -e "  - ${CYAN}Systemd${NC} (servicio squidstats)"
        
        echo -e "\n📋 ${YELLOW}COMANDOS ÚTILES:${NC}"
        echo -e "  Estado servicio: ${CYAN}systemctl status squidstats${NC}"
        echo -e "  Ver logs: ${CYAN}journalctl -u squidstats -f${NC}"
        echo -e "  Reiniciar: ${CYAN}systemctl restart squidstats${NC}"
        echo -e "  Logs detallados: ${CYAN}journalctl -u squidstats -n 50${NC}"
        
        local ip_address=$(hostname -I | awk '{print $1}')
        if [ -n "$ip_address" ]; then
            echo -e "\n🌐 ${YELLOW}ACCESO A LA APLICACIÓN:${NC}"
            echo -e "  URL: ${CYAN}http://$ip_address${NC}"
            echo -e "  URL local: ${CYAN}http://127.0.0.1${NC}"
        fi
    fi
    
    echo -e "\n📖 ${YELLOW}DOCUMENTACIÓN:${NC}"
    echo -e "  Repositorio: ${CYAN}https://github.com/kaelthasmanu/SquidStats${NC}"
}

function main_installation() {
    if [ "$IS_UPDATE" = true ]; then
        step "🔄 INICIANDO ACTUALIZACIÓN DE SQUIDSTATS"
    else
        step "🚀 INICIANDO INSTALACIÓN DE SQUIDSTATS"
    fi
    
    check_environment
    detect_install_mode
    
    echo -e "\n${YELLOW}=== RESUMEN DE ${NC}${CYAN}$([ "$IS_UPDATE" = true ] && echo "ACTUALIZACIÓN" || echo "INSTALACIÓN")${NC}${YELLOW} ===${NC}"
    echo -e "📁 Directorio: ${CYAN}$APP_DIR${NC}"
    echo -e "🐍 Entorno: ${CYAN}Python Virtual Environment${NC}"
    [ "$INSTALL_MODE" = "production" ] && echo -e "🔧 Servicios: ${CYAN}Nginx, Systemd${NC}"
    
    local prompt_message="¿Desea continuar con la $([ "$IS_UPDATE" = true ] && echo "actualización" || echo "instalación")?"
    if ! ask_yes_no "$prompt_message" "y"; then
        info "Operación cancelada por el usuario"
        exit 0
    fi
    
    if [ "$INSTALL_MODE" = "production" ]; then
        check_sudo
        setup_application_user
    fi
    
    install_system_dependencies
    check_and_install_squid
    setup_squid_permissions
    restart_squid_service
    clone_or_update_repository
    setup_python_environment
    create_environment_file
    configure_database
    
    if [ "$INSTALL_MODE" = "production" ]; then
        setup_nginx
        setup_systemd_service
        setup_logging
    fi
    
    set_permissions
    finalize_installation
}

function main() {
    case "${1:-}" in
        "--update") 
            IS_UPDATE=true
            # Modo actualización - detección automática
            step "🔄 INICIANDO ACTUALIZACIÓN DE SQUIDSTATS"
            
            # Detectar instalaciones existentes directamente
            if [ -f "$DEFAULT_PROD_DIR/.env" ] || (check_systemd && systemctl is-active --quiet squidstats 2>/dev/null); then
                INSTALL_MODE="production"
                APP_DIR="$DEFAULT_PROD_DIR"
                info "✅ Instalación de producción detectada en: $APP_DIR"
            elif [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -f "$DEVELOPMENT_DIR/.env" ]; then
                INSTALL_MODE="development"
                if [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -d "$DEVELOPMENT_DIR/SquidStats/.git" ]; then
                    APP_DIR="$DEVELOPMENT_DIR/SquidStats"
                else
                    APP_DIR="$DEVELOPMENT_DIR"
                fi
                info "✅ Instalación de desarrollo detectada en: $APP_DIR"
            else
                error "No se pudo detectar ninguna instalación de SquidStats para actualizar"
                info "Instalaciones buscadas:"
                info "  - Producción: $DEFAULT_PROD_DIR"
                info "  - Desarrollo: $DEVELOPMENT_DIR"
                info "Use './install.sh' sin opciones para una instalación nueva"
                exit 1
            fi
            
            # Continuar con la actualización
            main_installation
            ;;
        "--uninstall") 
            # Modo desinstalación - detección automática
            step "Modo desinstalación detectado"
            
            # Detectar instalaciones existentes directamente
            if [ -f "$DEFAULT_PROD_DIR/.env" ] || (check_systemd && systemctl is-active --quiet squidstats 2>/dev/null); then
                INSTALL_MODE="production"
                APP_DIR="$DEFAULT_PROD_DIR"
                info "Instalación de producción detectada en: $APP_DIR"
            elif [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -f "$DEVELOPMENT_DIR/.env" ]; then
                INSTALL_MODE="development"
                if [ -f "$DEVELOPMENT_DIR/SquidStats/.env" ] || [ -d "$DEVELOPMENT_DIR/SquidStats/.git" ]; then
                    APP_DIR="$DEVELOPMENT_DIR/SquidStats"
                else
                    APP_DIR="$DEVELOPMENT_DIR"
                fi
                info "Instalación de desarrollo detectada en: $APP_DIR"
            else
                error "No se pudo detectar ninguna instalación de SquidStats"
                info "Busca manualmente en:"
                info "  - Producción: $DEFAULT_PROD_DIR"
                info "  - Desarrollo: $DEVELOPMENT_DIR"
                exit 1
            fi
            
            echo -e "${YELLOW}⚠️  ESTA OPERACIÓN DESINSTALARÁ SQUIDSTATS DEL SISTEMA${NC}"
            echo -e "Modo detectado: ${CYAN}$INSTALL_MODE${NC}"
            echo -e "Directorio: ${CYAN}$APP_DIR${NC}"
            echo -e "Usuario del servicio: ${CYAN}squidstats${NC}"
            
            if ! ask_yes_no "¿Está seguro de que desea continuar?" "n"; then
                info "Desinstalación cancelada"
                exit 0
            fi
            
            # Proceder con desinstalación
            step "Iniciando desinstalación"
            
            # Detener y eliminar servicios (solo producción)
            if [ "$INSTALL_MODE" = "production" ]; then
                info "Deteniendo servicios..."
                systemctl stop squidstats.service 2>/dev/null || true
                systemctl disable squidstats.service 2>/dev/null || true
                rm -f /etc/systemd/system/squidstats.service
                systemctl daemon-reload
                
                # Eliminar configuración nginx
                rm -f /etc/nginx/sites-available/squidstats
                rm -f /etc/nginx/sites-enabled/squidstats
                if command -v nginx &> /dev/null; then
                    nginx -t && systemctl reload nginx 2>/dev/null || true
                fi
                
                # Eliminar logrotate
                rm -f /etc/logrotate.d/squidstats
                
                # Eliminar usuario
                userdel squidstats 2>/dev/null || true
                
                # Eliminar directorios de aplicación
                info "Eliminando archivos de aplicación..."
                rm -rf "$DEFAULT_PROD_DIR"
                rm -rf /var/log/squidstats
                rm -rf /var/run/squidstats
            else
                # En desarrollo, solo eliminar el entorno virtual
                info "Eliminando entorno virtual..."
                rm -rf "$APP_DIR/venv"
                info "Archivos de aplicación se mantienen en: $APP_DIR"
            fi
            
            success "✅ SquidStats ha sido desinstalado"
            
            if [ "$INSTALL_MODE" = "development" ]; then
                echo -e "\n${YELLOW}Nota:${NC} Los archivos de la aplicación se mantienen en ${CYAN}$APP_DIR${NC}"
                echo "Puede eliminarlos manualmente si lo desea: rm -rf $APP_DIR"
            fi
            ;;
        "--help"|"-h")
            echo -e "${CYAN}Uso: $0 [OPCIÓN]${NC}"
            echo "  Sin opciones    Instala SquidStats"
            echo "  --update        Actualiza instalación existente"
            echo "  --uninstall     Desinstala SquidStats"
            echo "  --help, -h      Muestra esta ayuda"
            ;;
        "")
            # Instalación normal - usa el menú interactivo
            main_installation
            ;;
        *)
            error "Parámetro no reconocido: $1"
            echo "Uso: $0 [--update|--uninstall|--help]"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi