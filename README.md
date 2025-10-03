# Pterodactyl Panel & Wings Installer

Script otomatis untuk menginstall dan menguninstall Pterodactyl Panel & Wings dengan dukungan tema.

Dibuat oleh **Gurita Darat**

## 🔥 Fitur

- ✅ Install Pterodactyl Panel otomatis
- ✅ Install Wings otomatis  
- ✅ Install/Uninstall tema
- ✅ Support multiple OS (Ubuntu, Debian, CentOS, Rocky Linux, Fedora)
- ✅ Konfigurasi otomatis (Nginx, MySQL, PHP)
- ✅ Pembuatan user administrator otomatis
- ✅ Logging komprehensif
- ✅ Validasi dependensi

## 📋 Persyaratan Sistem

- OS: Ubuntu 18.04+, Debian 10+, CentOS 8+, Rocky Linux 8+, Fedora 35+
- RAM: Minimum 2GB (Rekomendasi 4GB+)
- Storage: Minimum 10GB
- User: Root access

## 🚀 Instalasi Cepat

### Menggunakan curl (Recomended)

```bash
# Download dan install panel
curl -sSL https://raw.githubusercontent.com/miminnbokep/pterodactyl-install/main/install.sh | bash -s -- --install-panel --panel-url https://panel.domain.com

# Download dan install wings
curl -sSL https://raw.githubusercontent.com/miminnbokep/pterodactyl-install/main/install.sh | bash -s -- --install-wings

# Install tema
curl -sSL https://raw.githubusercontent.com/miminnbokep/pterodactyl-install/main/install.sh | bash -s -- --install-theme --theme-repo https://github.com/user/theme-repo
