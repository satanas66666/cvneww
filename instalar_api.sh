#!/bin/bash

echo "🔥 Instalando API VPS PRO (CORREGIDO)..."

# =========================
# CONFIG
# =========================
RUTA="/etc/chido"
PUERTO="8888"
SERVICIO="api-vps"
TOKEN="ULTRA_SECRET_TOKEN"

# =========================
# LIMPIAR
# =========================
systemctl stop $SERVICIO 2>/dev/null
systemctl disable $SERVICIO 2>/dev/null
pkill -f "php -S" 2>/dev/null

# =========================
# CREAR DIRECTORIOS
# =========================
mkdir -p $RUTA
mkdir -p /etc/SSHPlus/blocked
mkdir -p /etc/SSHPlus/limits

# =========================
# CREAR API (SIN ERRORES)
# =========================
cat > $RUTA/api.php <<'EOF'
<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo "pong";
    exit;
}

$TOKEN = "ULTRA_SECRET_TOKEN";

$data = json_decode(file_get_contents("php://input"), true);

if (!$data) {
    http_response_code(400);
    exit("JSON inválido");
}

if (!isset($data['token']) || $data['token'] !== $TOKEN) {
    http_response_code(403);
    exit("No autorizado");
}

$user = preg_replace('/[^a-zA-Z0-9._-]/', '', $data['user'] ?? '');
$pass  = $data['pass'] ?? '';
$dias  = intval($data['dias'] ?? 0);
$accion = $data['accion'] ?? '';
$fecha = $data['fecha'] ?? '';
// 🔥 NUEVO (OBLIGATORIO para temporales)
$tipo   = $data['tipo'] ?? 'normal';
$tiempo = intval($data['tiempo'] ?? 0);

function run($cmd){
    return shell_exec("sudo $cmd 2>&1");
}

if (in_array($accion, ["crear","eliminar","bloquear","desbloquear","editar","reset"]) && empty($user)) {
    exit("Usuario inválido");
}

switch ($accion) {

    case "crear":

    run("id $user || useradd -M -s /bin/false $user");

    if (!empty($pass)) {
        run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
    }

    // =========================
    // 🔥 TEMPORAL (PRO LIMPIO)
    // =========================
    if (isset($tipo) && $tipo == "temporal" && $tiempo > 0) {

        $expira = time() + ($tiempo * 60);

        // crear archivo si no existe
        if (!file_exists("/etc/vpn_temp_users")) {
            file_put_contents("/etc/vpn_temp_users", "");
        }

        // 🔥 evitar duplicados
        $lines = file("/etc/vpn_temp_users");
        $new = "";

        foreach ($lines as $line) {
            if (strpos($line, $user . "|") !== 0) {
                $new .= $line;
            }
        }

        // guardar actualizado
        $new .= "$user|$expira\n";
        file_put_contents("/etc/vpn_temp_users", $new);

    } else {

        // =========================
        // 🟢 NORMAL (TU LÓGICA ORIGINAL)
        // =========================
        if (!empty($fecha)) {

            run("chage -E $fecha $user");

        } elseif ($dias > 0) {

            if ($dias <= 0) $dias = 1;

            $exp = date("Y-m-d", strtotime("+$dias days"));
            run("chage -E $exp $user");
        }
    }

break;

    case "eliminar":
        run("pkill -KILL -u $user");
        run("killall -u $user");
        run("userdel -f $user");
        @unlink("/etc/SSHPlus/limits/$user");
        @unlink("/etc/SSHPlus/blocked/$user");
    break;

    case "bloquear":
        run("usermod -L $user");
        run("usermod -s /bin/false $user");
        run("pkill -KILL -u $user");
        file_put_contents("/etc/SSHPlus/blocked/$user", "blocked");
    break;

    case "desbloquear":
        run("usermod -U $user");
        run("usermod -s /bin/bash $user");
        @unlink("/etc/SSHPlus/blocked/$user");
    break;

    case "editar":

        if ($dias > 0) {

            $raw = run("chage -l $user | grep 'Account expires'");
            $fecha_actual = "";

            if ($raw) {
                $parts = explode(":", $raw);
                $fecha_actual = trim($parts[1]);
            }

            if ($fecha_actual == "" || strtolower($fecha_actual) == "never") {
                $base = time();
            } else {
                $base = strtotime($fecha_actual);
            }

            if ($base < time()) {
                $base = time();
            }

            $nueva_fecha = strtotime("+$dias days", $base);
            $formato = date("Y-m-d", $nueva_fecha);

            run("chage -E $formato $user");
        }

        if (!empty($fecha)) {
            run("chage -E $fecha $user");
        }

    break;

    case "reset":
        if (!empty($pass)) {
            run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        }
    break;

    case "limpiar_expirados":

        $users = explode("\n", trim(shell_exec("awk -F: '$3>=1000 {print $1}' /etc/passwd")));

        foreach ($users as $u) {

            if (empty($u)) continue;

            if (file_exists("/etc/SSHPlus/blocked/$u")) {
                continue;
            }

            $expire_raw = shell_exec("chage -l $u 2>/dev/null | grep 'Account expires'");
            $expire = "";

            if ($expire_raw) {
                $parts = explode(":", $expire_raw);
                $expire = trim($parts[1]);
            }

            if ($expire == "never" || empty($expire)) continue;

            $exp_date = strtotime($expire);
            $today = time();

            if (!$exp_date) continue;

            if ($today >= $exp_date) {

                run("pkill -KILL -u $u");
                run("killall -u $u");
                run("userdel -f $u");

                @unlink("/etc/SSHPlus/limits/$u");
                @unlink("/etc/SSHPlus/blocked/$u");
                @unlink("/etc/SSHPlus/abuse/$u");
            }
        }

        echo "cleaned";

    break;

    default:
        exit("Acción inválida");
}

echo "OK";
EOF

# =========================
# ROUTER
# =========================
cat > $RUTA/router.php <<'EOF'
<?php
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

if ($uri === '/api.php') {
    require __DIR__ . '/api.php';
    return;
}

return false;
EOF

# =========================
# PERMISOS
# =========================
chmod -R 755 $RUTA

# =========================
# SUDO
# =========================
if ! grep -q "www-data ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# =========================
# SERVICIO
# =========================
cat > /etc/systemd/system/$SERVICIO.service <<EOF
[Unit]
Description=API VPS PRO
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO $RUTA/router.php
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# =========================
# ACTIVAR
# =========================
systemctl daemon-reload
systemctl enable $SERVICIO
systemctl restart $SERVICIO

# =========================
# FIREWALL
# =========================
ufw allow $PUERTO 2>/dev/null

echo ""
echo "✅ API VPS PRO INSTALADA CORRECTAMENTE"
echo "🌐 http://IP_VPS:$PUERTO/api.php"
echo ""
echo "👉 PRUEBA:"
echo "curl http://127.0.0.1:$PUERTO/api.php"
