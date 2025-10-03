#!/bin/bash

# Pterodactyl Panel & Wings Installer/Uninstaller
# Created by Gurita Darat

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
PANEL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_SERVICE_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
MYSQL_ROOT_PASSWORD=""
PANEL_URL=""
PANEL_SSL="false"
THEME_REPO=""

# Logging
LOG_FILE="/var/log/pterodactyl-installer.log"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Script ini harus dijalankan sebagai root!"
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    else
        error "Tidak dapat mendeteksi OS"
    fi
    
    info "Detected OS: $OS $VER"
}

# Install dependencies
install_dependencies() {
    log "Menginstall dependencies sistem..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        apt update
        apt upgrade -y
        apt install -y curl wget git zip unzip tar software-properties-common
        apt install -y nginx mysql-server php8.1 php8.1-{cli,common,curl,zip,gd,mysql,mbstring,xml,bcmath,fpm} redis-server
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Rocky"* ]] || [[ "$OS" == *"Fedora"* ]]; then
        dnf update -y
        dnf install -y curl wget git zip unzip tar
        dnf install -y nginx mysql-server php81 php81-php-{cli,common,curl,zip,gd,mysqlnd,mbstring,xml,bcmath,fpm} redis
    else
        error "OS tidak didukung: $OS"
    fi
}

# Configure MySQL
setup_mysql() {
    log "Mengkonfigurasi MySQL..."
    
    systemctl enable mysql
    systemctl start mysql
    
    # Generate random password if not set
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
        echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD" >> /root/mysql_credentials.txt
    fi
    
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';"
    mysql -e "FLUSH PRIVILEGES;"
}

# Install Panel
install_panel() {
    log "Menginstall Pterodactyl Panel..."
    
    # Create panel user
    useradd -r -d /var/www/pterodactyl -s /bin/bash pterodactyl
    
    # Download panel
    cd /var/www
    curl -Lo panel.tar.gz $PANEL_URL
    tar -xzvf panel.tar.gz
    chmod -R 755 pterodactyl/
    chown -R pterodactyl:pterodactyl pterodactyl/
    
    # Install composer dependencies
    cd pterodactyl
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    composer install --no-dev --optimize-autoloader
    
    # Set permissions
    chown -R pterodactyl:pterodactyl /var/www/pterodactyl/*
    chmod -R 755 /var/www/pterodactyl/*
    chmod -R 755 /var/www/pterodactyl/storage/*
    chmod -R 755 /var/www/pterodactyl/bootstrap/cache/
    
    # Create database
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE panel;"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"
    
    # Setup environment
    cp .env.example .env
    php artisan key:generate --force
    
    # Update .env file
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_ROOT_PASSWORD}/" .env
    sed -i "s/APP_URL=.*/APP_URL=${PANEL_URL}/" .env
    
    # Run migrations and seed
    php artisan migrate --seed --force
    
    # Create first user
    info "Membuat user administrator..."
    php artisan p:user:make
    
    # Setup cron
    (crontab -l ; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -u pterodactyl -
    
    # Setup nginx
    setup_nginx
}

# Setup Nginx
setup_nginx() {
    log "Mengkonfigurasi Nginx..."
    
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name ${PANEL_URL#*://};
    root /var/www/pterodactyl/public;
    index index.php;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    nginx -t
    systemctl restart nginx
    systemctl enable nginx php8.1-fpm
}

# Install Wings
install_wings() {
    log "Menginstall Pterodactyl Wings..."
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings $WINGS_SERVICE_URL
    chmod +x /usr/local/bin/wings
    
    # Create wings service
    cat > /etc/systemd/system/wings.service << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wings
    systemctl start wings
    
    info "Wings berhasil diinstall. Silakan konfigurasi melalui panel."
}

# Check if panel is installed
check_panel_installed() {
    if [[ ! -d "/var/www/pterodactyl" ]]; then
        error "Pterodactyl Panel belum terinstall. Silakan install panel terlebih dahulu."
    fi
}

# Install theme
install_theme() {
    check_panel_installed
    
    if [[ -z "$THEME_REPO" ]]; then
        read -p "Masukkan URL repository theme GitHub: " THEME_REPO
    fi
    
    log "Menginstall theme dari: $THEME_REPO"
    
    cd /var/www/pterodactyl
    sudo -u pterodactyl git clone $THEME_REPO temp_theme
    
    # Copy theme files
    cp -r temp_theme/* .
    rm -rf temp_theme
    
    # Rebuild assets
    sudo -u pterodactyl php artisan view:clear
    sudo -u pterodactyl php artisan config:clear
    sudo -u pterodactyl npm run build:production
    
    log "Theme berhasil diinstall!"
}

# Uninstall theme
uninstall_theme() {
    check_panel_installed
    
    log "Menguninstall theme..."
    
    cd /var/www/pterodactyl
    sudo -u pterodactyl git reset --hard
    sudo -u pterodactyl git clean -fd
    
    # Rebuild default assets
    sudo -u pterodactyl php artisan view:clear
    sudo -u pterodactyl php artisan config:clear
    sudo -u pterodactyl npm run build:production
    
    log "Theme berhasil diuninstall!"
}

# Uninstall panel
uninstall_panel() {
    warn "Tindakan ini akan menghapus Pterodactyl Panel secara permanen!"
    read -p "Apakah Anda yakin? (y/N): " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        info "Uninstall dibatalkan."
        exit 0
    fi
    
    log "Menguninstall Pterodactyl Panel..."
    
    # Stop services
    systemctl stop nginx
    systemctl stop php8.1-fpm
    systemctl disable nginx php8.1-fpm
    
    # Remove panel files
    rm -rf /var/www/pterodactyl
    userdel pterodactyl
    
    # Remove nginx config
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    
    # Remove database
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "DROP DATABASE panel;"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "DROP USER 'pterodactyl'@'127.0.0.1';"
    
    # Remove cron
    crontab -u pterodactyl -r
    
    log "Pterodactyl Panel berhasil diuninstall!"
}

# Uninstall wings
uninstall_wings() {
    log "Menguninstall Wings..."
    
    systemctl stop wings
    systemctl disable wings
    rm -f /usr/local/bin/wings
    rm -f /etc/systemd/system/wings.service
    rm -rf /etc/pterodactyl
    systemctl daemon-reload
    
    log "Wings berhasil diuninstall!"
}

# Show usage
show_usage() {
    echo "Pterodactyl Panel & Wings Installer"
    echo "Penggunaan: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --install-panel          Install Pterodactyl Panel"
    echo "  --install-wings          Install Pterodactyl Wings"
    echo "  --install-theme          Install theme"
    echo "  --uninstall-panel        Uninstall Pterodactyl Panel"
    echo "  --uninstall-wings        Uninstall Wings"
    echo "  --uninstall-theme        Uninstall theme"
    echo "  --panel-url URL          Set panel URL (required for panel install)"
    echo "  --theme-repo URL         Set theme repository URL"
    echo "  --mysql-password PASS    Set MySQL root password"
    echo "  --help                   Show this help message"
    echo ""
    echo "CONTOH:"
    echo "  $0 --install-panel --panel-url https://panel.example.com"
    echo "  $0 --install-theme --theme-repo https://github.com/user/theme"
    echo ""
}

# Main function
main() {
    check_root
    detect_os
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-panel)
                INSTALL_PANEL=true
                shift
                ;;
            --install-wings)
                INSTALL_WINGS=true
                shift
                ;;
            --install-theme)
                INSTALL_THEME=true
                shift
                ;;
            --uninstall-panel)
                UNINSTALL_PANEL=true
                shift
                ;;
            --uninstall-wings)
                UNINSTALL_WINGS=true
                shift
                ;;
            --uninstall-theme)
                UNINSTALL_THEME=true
                shift
                ;;
            --panel-url)
                PANEL_URL="$2"
                shift 2
                ;;
            --theme-repo)
                THEME_REPO="$2"
                shift 2
                ;;
            --mysql-password)
                MYSQL_ROOT_PASSWORD="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Option tidak dikenal: $1"
                ;;
        esac
    done
    
    # Execute actions
    if [[ "$INSTALL_PANEL" == "true" ]]; then
        if [[ -z "$PANEL_URL" ]]; then
            error "Panel URL diperlukan (--panel-url)"
        fi
        install_dependencies
        setup_mysql
        install_panel
    fi
    
    if [[ "$INSTALL_WINGS" == "true" ]]; then
        install_wings
    fi
    
    if [[ "$INSTALL_THEME" == "true" ]]; then
        install_theme
    fi
    
    if [[ "$UNINSTALL_PANEL" == "true" ]]; then
        uninstall_panel
    fi
    
    if [[ "$UNINSTALL_WINGS" == "true" ]]; then
        uninstall_wings
    fi
    
    if [[ "$UNINSTALL_THEME" == "true" ]]; then
        uninstall_theme
    fi
    
    if [[ $# -eq 0 ]]; then
        show_usage
    fi
}

# Run main function
main "$@"