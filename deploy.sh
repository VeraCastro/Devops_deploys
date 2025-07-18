#!/bin/bash
# Script de instalación de phpMyFAQ para Vagrant (Rocky Linux 8)

# Configuración de variables (para mayor claridad)
PHP_FPM_CONF_D="/etc/php-fpm.d"
PHP_FPM_MAIN_CONF="/etc/php-fpm.conf"
APACHE_CONF_D="/etc/httpd/conf.d"
PHP_MYFAQ_ROOT="/var/www/html/phpmyfaq"
PHP_FPM_PORT="9000"
PHP_FPM_LISTEN_ADDR="127.0.0.1"


echo "Iniciando aprovisionamiento de phpMyFAQ en Rocky Linux 8..."

# Actualizar el sistema e instalar herramientas básicas
echo "Actualizando el sistema e instalando nano..."
dnf update -y
dnf install -y nano -y

# Instalar repositorio EPEL para Rocky Linux 8
echo "Instalando repositorio EPEL para Rocky Linux 8..."
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y

# Instalar dnf-plugins-core (necesario para 'dnf module')
echo "Instalando dnf-plugins-core..."
dnf install -y dnf-plugins-core -y

# Instalar el repositorio Remi (primero, antes de habilitar módulos PHP de Remi)
echo "Instalando el repositorio Remi para Rocky 8..."
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y

# Habilitar el módulo PHP 8.2 de Remi y deshabilitar otros streams de PHP
echo "Configurando módulo PHP 8.2 de Remi y reseteando otros streams de PHP..."
dnf module reset php -y
dnf module enable php:remi-8.2 -y

# Instalar Apache
echo "Instalando Apache HTTP Server..."
dnf install -y httpd -y
systemctl start httpd
systemctl enable httpd

# Asegurar que el módulo MPM event de Apache esté cargado
echo "Configurando Apache MPM (event_module)..."
# Comentar todos los MPMs para evitar conflictos, y luego habilitar solo event_module
sudo sed -i '/^LoadModule mpm_.*_module/s/^/#/' /etc/httpd/conf/httpd.conf
sudo sed -i '/#LoadModule mpm_event_module/s/^#//' /etc/httpd/conf/httpd.conf


# Instalar PHP 8.2 y extensiones requeridas (incluyendo php-fpm) desde Remi
echo "Instalando PHP 8.2 y extensiones requeridas (incluyendo php-fpm)..."
dnf install -y php php-cli php-fpm php-common php-curl php-gd php-xml php-mbstring php-mysqlnd php-intl php-zip php-opcache php-json php-fileinfo
php -v # Verificar la versión de PHP instalada

# Instalar MariaDB
echo "Instalando MariaDB Server..."
dnf install -y mariadb-server -y
systemctl start mariadb
systemctl enable mariadb

# Instalar Node.js 22 usando nvm
echo "Instalando Node.js 22 vía nvm..."
dnf install -y curl git -y
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Configurar entorno NVM para la sesión actual del script
export NVM_DIR="/root/.nvm" # Asumiendo ejecución como root por Vagrant
if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
    echo "NVM script sourced."
else
    echo "NVM script no encontrado en $NVM_DIR/nvm.sh. La instalación de Node.js podría fallar."
fi

if [ -s "$NVM_DIR/bash_completion" ]; then
    \. "$NVM_DIR/bash_completion"
fi

nvm install 22
nvm use 22
nvm alias default 22

# Verificar versión de Node.js
echo "Versión de Node.js instalada:"
node -v || echo "Node.js no se instaló correctamente."

# Instalar pnpm globalmente
echo "Instalando pnpm globalmente..."
npm install -g pnpm || echo "Falló la instalación de pnpm."

# Configurar MariaDB - crear base de datos y usuario
echo "Configurando MariaDB - Creando base de datos y usuario para phpMyFAQ..."
DB_NAME="phpmyfaq"
DB_USER="phpmyfaquser"
DB_PASS="PhpMyFAQ$(date +%s | sha256sum | base64 | head -c 12)" # Genera contraseña aleatoria

# Guardar credenciales para referencia
echo "Guardando credenciales de la base de datos en /root/phpmyfaq_credentials.txt..."
echo "Base de datos: $DB_NAME" > /root/phpmyfaq_credentials.txt
echo "Usuario: $DB_USER" >> /root/phpmyfaq_credentials.txt
echo "Contraseña: $DB_PASS" >> /root/phpmyfaq_credentials.txt
chmod 600 /root/phpmyfaq_credentials.txt

# Comandos SQL para configurar la base de datos (usando here document para mayor robustez)
mysql <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo "Base de datos y usuario creados."

# Eliminar directorio phpMyFAQ si ya existe
if [ -d "$PHP_MYFAQ_ROOT" ]; then
    echo "Eliminando directorio phpMyFAQ existente..."
    rm -rf "$PHP_MYFAQ_ROOT"
fi

# Descargar e instalar phpMyFAQ
echo "Descargando e instalando phpMyFAQ 4.0.7..."
cd /var/www/html
wget https://download.phpmyfaq.de/phpMyFAQ-4.0.7.tar.gz
tar -xzf phpMyFAQ-4.0.7.tar.gz
mv phpMyFAQ-4.0.7 phpmyfaq
rm phpMyFAQ-4.0.7.tar.gz

# Configurar permisos y propiedades para phpMyFAQ
echo "Configurando permisos y propiedades de archivos y directorios para phpMyFAQ..."
chown -R apache:apache "$PHP_MYFAQ_ROOT"
find "$PHP_MYFAQ_ROOT" -type d -exec chmod 775 {} + # Directorios 775
find "$PHP_MYFAQ_ROOT" -type f -exec chmod 664 {} + # Archivos 664

# Crear y asegurar permisos específicos para directorios de datos y configuración (más sensibles)
echo "Creando y ajustando permisos para directorios sensibles de phpMyFAQ..."
declare -a DATA_DIRS=(
    "$PHP_MYFAQ_ROOT/data"
    "$PHP_MYFAQ_ROOT/images"
    "$PHP_MYFAQ_ROOT/config"
    "$PHP_MYFAQ_ROOT/content/core/config"
    "$PHP_MYFAQ_ROOT/content/core/data"
    "$PHP_MYFAQ_ROOT/content/user/images"
    "$PHP_MYFAQ_ROOT/content/user/attachments"
)

for dir in "${DATA_DIRS[@]}"; do
    mkdir -p "$dir"
    chown -R apache:apache "$dir"
    chmod -R 775 "$dir" # 775 para que Apache (propietario) y grupo (php-fpm si es necesario) puedan escribir
done
echo "Permisos específicos de directorios data, images, config y content establecidos a 775."


# --- CONFIGURACIÓN DE APACHE Y PHP-FPM ---

# Deshabilitar configuración predeterminada de PHP de Apache (php.conf)
echo "Deshabilitando /etc/httpd/conf.d/php.conf para evitar conflictos..."
if [ -f "$APACHE_CONF_D/php.conf" ]; then
    sudo mv "$APACHE_CONF_D/php.conf" "$APACHE_CONF_D/php.conf.disabled"
    echo "$APACHE_CONF_D/php.conf renombrado a .disabled"
else
    echo "$APACHE_CONF_D/php.conf no encontrado, no se necesita deshabilitar."
fi

# Crear archivo de configuración de Apache para phpMyFAQ
echo "Creando configuración de VirtualHost de Apache para phpMyFAQ..."
cat > "$APACHE_CONF_D/phpmyfaq.conf" << 'EOL'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/phpmyfaq
    ErrorLog /var/log/httpd/phpmyfaq-error.log
    CustomLog /var/log/httpd/phpmyfaq-access.log combined
    <Directory /var/www/html/phpmyfaq>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

# === INICIO DE CAMBIO CRÍTICO PARA PHP-FPM www.conf ===
# Eliminar el www.conf existente y crear uno nuevo de cero para evitar problemas de caracteres/sintaxis
echo "Recreando el archivo ${PHP_FPM_CONF_D}/www.conf desde cero para asegurar la sintaxis correcta..."
# Guarda el archivo original si quieres depurar, sino simplemente bórralo.
# sudo mv "${PHP_FPM_CONF_D}/www.conf" "${PHP_FPM_CONF_D}/www.conf.bak" 
sudo rm -f "${PHP_FPM_CONF_D}/www.conf" # Elimina el archivo existente

cat > "${PHP_FPM_CONF_D}/www.conf" << EOL
[www]
user = apache
group = apache
listen = ${PHP_FPM_LISTEN_ADDR}:${PHP_FPM_PORT}
listen.owner = apache
listen.group = apache
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.process_idle_timeout = 10s
pm.max_requests = 500
;php_admin_value[disable_functions] = passthru, system, popen, pclose, shell_exec, exec, proc_open, proc_close, proc_terminate, proc_get_status, proc_nice, show_source, symlink, link
;php_admin_flag[allow_url_fopen] = off
php_flag[display_errors] = off
php_admin_value[error_log] = /var/log/php-fpm/www-error.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = 256M
catch_workers_output = yes
clear_env = no
EOL
echo "Archivo ${PHP_FPM_CONF_D}/www.conf recreado con configuración TCP/IP."
# === FIN DEL CAMBIO CRÍTICO ===


# Asegurar que /etc/php-fpm.conf incluya los archivos de pool de php-fpm.d/
echo "Asegurando que ${PHP_FPM_MAIN_CONF} incluya los archivos de pool de ${PHP_FPM_CONF_D}/..."
# Descomentar la línea include para los archivos de pool, si está comentada
# Maneja rutas relativas y absolutas
sudo sed -i 's|^;include=etc/php-fpm.d/\*.conf|include=etc/php-fpm.d/\*.conf|g' "$PHP_FPM_MAIN_CONF"
sudo sed -i 's|^;include=/etc/php-fpm.d/\*.conf|include=/etc/php-fpm.d/\*.conf|g' "$PHP_FPM_MAIN_CONF"


# Crear archivo de configuración de Apache para PHP-FPM (proxy_fcgi)
echo "Creando configuración de Apache para integrar con PHP-FPM (proxy_fcgi)..."
cat > "$APACHE_CONF_D/php-fpm.conf" << EOL
<IfModule proxy_fcgi_module>
    # Configuración principal para pasar solicitudes .php a PHP-FPM
    # Usamos ProxyPassMatch para un manejo más flexible y explícito
    ProxyPassMatch ^/(.*\.php(/.*)?)\$ fcgi://${PHP_FPM_LISTEN_ADDR}:${PHP_FPM_PORT}${PHP_MYFAQ_ROOT}/\$1

    # Asegura que el módulo dir esté habilitado y que index.php esté en la lista
    <IfModule dir_module>
        DirectoryIndex index.php index.html
    </IfModule>
</IfModule>
EOL


# --- INICIO DE SERVICIOS Y SELINUX ---

# Iniciar y habilitar PHP-FPM
echo "Iniciando y habilitando PHP-FPM..."
systemctl restart php-fpm # restart por si ya estaba corriendo en un estado "malo"
systemctl enable php-fpm

# Configurar Firewalld para permitir el tráfico a PHP-FPM y HTTP/HTTPS
echo "Configurando Firewalld para permitir tráfico HTTP/HTTPS y PHP-FPM..."
sudo systemctl start firewalld # Asegurarse de que el servicio de firewalld esté corriendo
sudo systemctl enable firewalld

# Añadir reglas para el puerto de PHP-FPM (9000/tcp)
if ! sudo firewall-cmd --zone=public --query-port=${PHP_FPM_PORT}/tcp; then
    sudo firewall-cmd --zone=public --add-port=${PHP_FPM_PORT}/tcp --permanent
    echo "Puerto ${PHP_FPM_PORT}/tcp añadido a firewalld."
else
    echo "Puerto ${PHP_FPM_PORT}/tcp ya está en firewalld."
fi

# Añadir reglas para HTTP (80/tcp)
if ! sudo firewall-cmd --zone=public --query-port=80/tcp; then
    sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
    echo "Puerto 80/tcp añadido a firewalld."
else
    echo "Puerto 80/tcp ya está en firewalld."
fi

# Recargar Firewalld para aplicar los cambios
sudo firewall-cmd --reload
echo "Firewalld recargado."


# Configurar SELinux si está habilitado
echo "Configurando SELinux si está habilitado..."
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    dnf install -y policycoreutils-python-utils -y
    
    # Contextos para los directorios de phpMyFAQ (lectura/escritura para httpd)
    semanage fcontext -a -t httpd_sys_rw_content_t "${PHP_MYFAQ_ROOT}/data(/.*)?" || echo "semanage data failed"
    semanage fcontext -a -t httpd_sys_rw_content_t "${PHP_MYFAQ_ROOT}/images(/.*)?" || echo "semanage images failed"
    semanage fcontext -a -t httpd_sys_rw_content_t "${PHP_MYFAQ_ROOT}/config(/.*)?" || echo "semanage config failed"
    semanage fcontext -a -t httpd_sys_rw_content_t "${PHP_MYFAQ_ROOT}/content(/.*)?" || echo "semanage content failed"
    restorecon -Rv "$PHP_MYFAQ_ROOT" || echo "restorecon failed"

    # Booleanos de conexión de red para Apache
    echo "Habilitando booleanos SELinux para la conexión de red de Apache..."
    setsebool -P httpd_can_network_connect 1 || echo "setsebool httpd_can_network_connect failed"
    setsebool -P httpd_can_network_connect_db 1 || echo "setsebool httpd_can_network_connect_db failed" # Para conexión a DB por red, si aplica

    echo "SELinux configurado."
else
    echo "SELinux no está habilitado o getenforce no está disponible. No se aplicó configuración de SELinux."
fi

# Reiniciar Apache para aplicar todos los cambios de configuración
echo "Reiniciando Apache para aplicar todos los cambios..."
systemctl restart httpd

# --- INFORMACIÓN FINAL ---
echo "--------------------------------------------------------------------"
echo "INSTALACIÓN COMPLETADA"
echo "Accede a phpMyFAQ para finalizar la configuración en:"
echo "http://localhost:8888/setup/index.php"
echo "Credenciales de la base de datos (para el asistente de phpMyFAQ):"
echo "  Base de datos: $DB_NAME"
echo "  Usuario: $DB_USER"
echo "  Contraseña: $DB_PASS"
echo "Esta información también está en /root/phpmyfaq_credentials.txt"
echo "--------------------------------------------------------------------"
echo "Instalación de phpMyFAQ completada." >> /root/phpmyfaq_credentials.txt
echo "Accede a http://localhost:8888/setup/index.php para completar la configuración de phpMyFAQ" >> /root/phpmyfaq_credentials.txt
echo "Información de la base de datos y acceso guardada en /root/phpmyfaq_credentials.txt" >> /root/phpmyfaq_credentials.txt

