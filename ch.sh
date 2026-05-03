#!/bin/bash

clear

# =========================
# CONFIG
# =========================
ZIP_URL="https://raw.githubusercontent.com/satanas66666/cvneww/main/chido.zip"
CARPETA_ETC="/etc/chido"
TMP_DIR="/tmp/chido_install"

# =========================
# ANTI FREEZE UBUNTU 22
# =========================
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt-get update -y -o Dpkg::Options::="--force-confold" > /dev/null

apt-get install -y unzip curl php \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    > /dev/null 2>&1

# =========================
# DESCARGA
# =========================
rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR

echo "Descargando archivos..."

curl -L $ZIP_URL -o chido.zip

if [ ! -f chido.zip ]; then
    echo "Error al descargar el zip"
    exit 1
fi

# =========================
# VALIDAR ZIP
# =========================
unzip -t chido.zip > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Zip corrupto"
    exit 1
fi

# =========================
# BACKUP
# =========================
if [ -d "$CARPETA_ETC" ]; then
    echo "Backup anterior..."
    mv "$CARPETA_ETC" "${CARPETA_ETC}_backup_$(date +%s)"
fi

# =========================
# INSTALAR
# =========================
mkdir -p "$CARPETA_ETC"

unzip -q chido.zip -d extract

# Detectar estructura automática
BASE=$(find extract -type d -name "chidito1" | head -n1)

if [ -z "$BASE" ]; then
    echo "Error: no se encontró chidito1"
    exit 1
fi

BASE_DIR=$(dirname "$BASE")

cp -r "$BASE_DIR"/* "$CARPETA_ETC"

# Validaciones
if [ ! -f "$CARPETA_ETC/index.php" ]; then
    echo "Error: falta index.php"
    exit 1
fi

if [ ! -d "$CARPETA_ETC/chidito1" ]; then
    echo "Error: falta carpeta chidito1"
    exit 1
fi

# =========================
# ROUTER (checkUser limpio)
# =========================
cat > "$CARPETA_ETC/router.php" <<EOF
<?php
\$uri = urldecode(parse_url(\$_SERVER['REQUEST_URI'], PHP_URL_PATH));

if (\$uri === '/checkUser' || \$uri === '/checkUser/') {
    require __DIR__ . '/chidito1/index.php';
    return;
}

\$file = __DIR__ . \$uri;
if (\$uri !== '/' && file_exists(\$file)) {
    return false;
}

require __DIR__ . '/index.php';
EOF

# =========================
# BLOQUEO AUTOMÁTICO
# =========================
mkdir -p /etc/chido

cat > /etc/chido/block_expired.sh <<'EOF'
#!/bin/bash

for user in $(cut -d: -f1 /etc/passwd); do

    uid=$(id -u $user 2>/dev/null)

    if [[ "$uid" -lt 1000 ]]; then
        continue
    fi

    exp=$(chage -l $user 2>/dev/null | grep "Account expires" | cut -d: -f2)

    if [[ "$exp" == " never" || -z "$exp" ]]; then
        continue
    fi

    exp_date=$(date -d "$exp" +%s 2>/dev/null)
    today=$(date +%s)

    if [[ $today -ge $exp_date ]]; then
        usermod -L $user
    else
        usermod -U $user
    fi

done
EOF

chmod +x /etc/chido/block_expired.sh

# CRON automático
(crontab -l 2>/dev/null | grep -v block_expired; echo "* * * * * /etc/chido/block_expired.sh") | crontab -

# =========================
# PUERTOS
# =========================
echo ""
read -p "Puerto checkUser: " PUERTO_CHECK
read -p "Puerto panel: " PUERTO_PANEL

if ! [[ "$PUERTO_CHECK" =~ ^[0-9]+$ ]] || ! [[ "$PUERTO_PANEL" =~ ^[0-9]+$ ]]; then
    echo "Puertos inválidos"
    exit 1
fi

# =========================
# SERVICIOS
# =========================

cat > /etc/systemd/system/chido-check.service <<EOF
[Unit]
Description=Chido CheckUser
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_CHECK $CARPETA_ETC/router.php
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/chido-panel.service <<EOF
[Unit]
Description=Chido Panel
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_PANEL -t $CARPETA_ETC
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# =========================
# ACTIVAR
# =========================
systemctl daemon-reexec
systemctl daemon-reload

systemctl enable chido-check
systemctl enable chido-panel

systemctl restart chido-check
systemctl restart chido-panel

# =========================
# LIMPIEZA
# =========================
rm -rf $TMP_DIR

# =========================
# RESULTADO
# =========================
IP=$(hostname -I | awk '{print $1}')

clear
echo "======================================="
echo " INSTALADO NIVEL PRO 🚀"
echo "======================================="
echo ""
echo "CheckUser:"
echo "http://$IP:$PUERTO_CHECK/checkUser"
echo ""
echo "🔐 LOGIN PANEL:"
echo "http://$IP:$PUERTO_PANEL/login.php"
echo ""
echo "📊 PANEL ADMIN:"
echo "http://$IP:$PUERTO_PANEL/admin.php"
echo ""
echo "👤 Usuario: admin"
echo "🔑 Password: admin123"
echo ""
echo "Bloqueo automático: ACTIVO ✅"
echo ""
echo "======================================="
