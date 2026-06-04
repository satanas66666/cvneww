#!/bin/bash

echo "🔥 Instalando API VPS PRO + CheckUser (CORREGIDO)..."

RUTA="/etc/chido"
PUERTO="8888"
SERVICIO="api-vps"
TOKEN="ULTRA_SECRET_TOKEN"

systemctl stop "$SERVICIO" 2>/dev/null
systemctl disable "$SERVICIO" 2>/dev/null

# Mata solo el php de esta API para no tumbar otros php importantes
pkill -f "php -S 0.0.0.0:$PUERTO $RUTA/router.php" 2>/dev/null

mkdir -p "$RUTA"
mkdir -p /etc/SSHPlus/blocked
mkdir -p /etc/SSHPlus/limits
mkdir -p /etc/SSHPlus/abuse
touch /etc/vpn_temp_users

cat > "$RUTA/api.php" <<'EOF'
<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

$TOKEN = "ULTRA_SECRET_TOKEN";

/*
 * API principal:
 * POST /api.php
 *
 * Acciones:
 * crear, eliminar, bloquear, desbloquear, editar, reset, limpiar_expirados
 */

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo "pong";
    exit;
}

$data = json_decode(file_get_contents("php://input"), true);

if (!$data) {
    http_response_code(400);
    exit("JSON inválido");
}

if (!isset($data['token']) || $data['token'] !== $TOKEN) {
    http_response_code(403);
    exit("No autorizado");
}

$user   = preg_replace('/[^a-zA-Z0-9._-]/', '', $data['user'] ?? '');
$pass   = $data['pass'] ?? '';
$accion = $data['accion'] ?? '';
$fecha  = $data['fecha'] ?? '';

$tipo   = $data['tipo'] ?? 'normal';
$tiempo = intval($data['tiempo'] ?? 0);

/*
 * FIX:
 * El panel PHP manda "tiempo" para normal y temporal.
 * La API también acepta "dias".
 */
$dias   = intval($data['dias'] ?? ($data['tiempo'] ?? 0));
$limite = intval($data['limite'] ?? 0);

function run($cmd){
    return shell_exec("sudo $cmd 2>&1");
}

function limpiar_temp_user($user) {
    $tempFile = "/etc/vpn_temp_users";

    if (!file_exists($tempFile)) {
        return;
    }

    $lines = file($tempFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    $new = "";

    foreach ($lines as $line) {
        if (strpos($line, $user . "|") !== 0) {
            $new .= $line . "\n";
        }
    }

    file_put_contents($tempFile, $new);
}

if (in_array($accion, ["crear","eliminar","bloquear","desbloquear","editar","reset"]) && empty($user)) {
    exit("Usuario inválido");
}

switch ($accion) {

    case "crear":

        run("id " . escapeshellarg($user) . " || useradd -M -s /bin/false " . escapeshellarg($user));

        if (!empty($pass)) {
            run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        }

        if ($limite > 0) {
            if (!file_exists("/etc/SSHPlus/limits")) {
                mkdir("/etc/SSHPlus/limits", 0777, true);
            }
            file_put_contents("/etc/SSHPlus/limits/$user", $limite);
        }

        if ($tipo == "temporal" && $tiempo > 0) {

            $expira = time() + ($tiempo * 60);

            if (!file_exists("/etc/vpn_temp_users")) {
                file_put_contents("/etc/vpn_temp_users", "");
            }

            limpiar_temp_user($user);

            file_put_contents("/etc/vpn_temp_users", "$user|$expira\n", FILE_APPEND);

            /*
             * IMPORTANTE:
             * Para temporales NO usamos chage -E, porque chage trabaja por fecha/día.
             * El vencimiento exacto por minutos lo valida /checkUser leyendo /etc/vpn_temp_users.
             */

        } else {

            limpiar_temp_user($user);

            if (!empty($fecha)) {

                run("chage -E " . escapeshellarg($fecha) . " " . escapeshellarg($user));

            } elseif ($dias > 0) {

                $exp = date("Y-m-d", strtotime("+$dias days"));
                run("chage -E " . escapeshellarg($exp) . " " . escapeshellarg($user));
            }
        }

        echo "OK";
        exit;

    case "eliminar":

        run("pkill -KILL -u " . escapeshellarg($user));
        run("killall -u " . escapeshellarg($user));
        run("userdel -f " . escapeshellarg($user));

        @unlink("/etc/SSHPlus/limits/$user");
        @unlink("/etc/SSHPlus/blocked/$user");
        @unlink("/etc/SSHPlus/abuse/$user");

        limpiar_temp_user($user);

        echo "OK";
        exit;

    case "bloquear":

        run("usermod -L " . escapeshellarg($user));
        run("usermod -s /bin/false " . escapeshellarg($user));
        run("pkill -KILL -u " . escapeshellarg($user));
        run("killall -u " . escapeshellarg($user));

        file_put_contents("/etc/SSHPlus/blocked/$user", "blocked");

        echo "OK";
        exit;

    case "desbloquear":

        run("usermod -U " . escapeshellarg($user));
        run("usermod -s /bin/bash " . escapeshellarg($user));

        @unlink("/etc/SSHPlus/blocked/$user");

        echo "OK";
        exit;

    case "editar":

        if ($dias > 0) {

            limpiar_temp_user($user);

            $raw = run("chage -l " . escapeshellarg($user) . " | grep 'Account expires'");
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

            run("chage -E " . escapeshellarg($formato) . " " . escapeshellarg($user));
        }

        if (!empty($fecha)) {
            limpiar_temp_user($user);
            run("chage -E " . escapeshellarg($fecha) . " " . escapeshellarg($user));
        }

        /*
         * Permite editar temporal por minutos también:
         * accion=editar, tipo=temporal, tiempo=120
         */
        if ($tipo == "temporal" && $tiempo > 0) {
            $expira = time() + ($tiempo * 60);
            limpiar_temp_user($user);
            file_put_contents("/etc/vpn_temp_users", "$user|$expira\n", FILE_APPEND);
        }

        if ($limite > 0) {
            if (!file_exists("/etc/SSHPlus/limits")) {
                mkdir("/etc/SSHPlus/limits", 0777, true);
            }
            file_put_contents("/etc/SSHPlus/limits/$user", $limite);
        }

        echo "OK";
        exit;

    case "reset":

        if (!empty($pass)) {
            run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        }

        echo "OK";
        exit;

    case "limpiar_expirados":

        $users = explode("\n", trim(shell_exec("awk -F: '$3>=1000 {print $1}' /etc/passwd")));

        foreach ($users as $u) {

            if (empty($u)) continue;

            if (file_exists("/etc/SSHPlus/blocked/$u")) {
                continue;
            }

            /*
             * Limpiar temporales vencidos
             */
            if (file_exists("/etc/vpn_temp_users")) {
                $lines = file("/etc/vpn_temp_users", FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

                foreach ($lines as $line) {
                    $parts = explode("|", trim($line));

                    if (count($parts) >= 2 && trim($parts[0]) === $u) {
                        $expiraTemp = intval(trim($parts[1]));

                        if ($expiraTemp > 0 && time() >= $expiraTemp) {
                            run("pkill -KILL -u " . escapeshellarg($u));
                            run("killall -u " . escapeshellarg($u));
                            run("userdel -f " . escapeshellarg($u));

                            @unlink("/etc/SSHPlus/limits/$u");
                            @unlink("/etc/SSHPlus/blocked/$u");
                            @unlink("/etc/SSHPlus/abuse/$u");

                            limpiar_temp_user($u);
                            continue 2;
                        }
                    }
                }
            }

            $expire_raw = shell_exec("chage -l " . escapeshellarg($u) . " 2>/dev/null | grep 'Account expires'");
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

                run("pkill -KILL -u " . escapeshellarg($u));
                run("killall -u " . escapeshellarg($u));
                run("userdel -f " . escapeshellarg($u));

                @unlink("/etc/SSHPlus/limits/$u");
                @unlink("/etc/SSHPlus/blocked/$u");
                @unlink("/etc/SSHPlus/abuse/$u");

                limpiar_temp_user($u);
            }
        }

        echo "cleaned";
        exit;

    default:
        exit("Acción inválida");
}
EOF

cat > "$RUTA/checkUser.php" <<'EOF'
<?php

/*
 * CheckUser:
 * POST /checkUser
 * POST /index.php
 *
 * Entrada:
 * {"user":"usuario"}
 *
 * Salida:
 * Not exist
 * TEMP|timestamp
 * ddmmyyyy
 * 31122099
 */

$datos = file_get_contents("php://input");
$update = json_decode($datos, true);

$FORMATO = "dmY";

if (!isset($update) || !isset($update['user'])) {
    echo "Not exist";
    exit;
}

$userClean = preg_replace('/[^a-zA-Z0-9._-]/', '', trim($update['user'] ?? ''));

if ($userClean === "") {
    echo "Not exist";
    exit;
}

$usuario = escapeshellarg($userClean);

/*
 * VALIDAR USUARIO LINUX
 */
exec("id -u $usuario 2>/dev/null", $out, $code);

if ($code !== 0) {
    echo "Not exist";
    exit;
}

/*
 * VALIDAR BLOQUEO POR ARCHIVO
 */
if (file_exists("/etc/SSHPlus/blocked/$userClean")) {
    echo "Not exist";
    exit;
}

/*
 * VALIDAR BLOQUEO POR passwd -S
 */
$lockCheck = shell_exec("passwd -S $usuario 2>/dev/null");

if ($lockCheck && strpos($lockCheck, ' L ') !== false) {
    echo "Not exist";
    exit;
}

/*
 * VALIDAR SHELL
 * Permitimos /bin/false porque muchos paneles crean usuarios así.
 * Solo bloqueamos nologin.
 */
$shellCheck = trim(shell_exec("getent passwd $usuario | cut -d: -f7"));

if ($shellCheck && strpos($shellCheck, 'nologin') !== false) {
    echo "Not exist";
    exit;
}

/*
 * USUARIO TEMPORAL POR MINUTOS
 */
$tempFile = "/etc/vpn_temp_users";

if (file_exists($tempFile)) {
    $lineas = file($tempFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    foreach ($lineas as $linea) {
        $partes = explode("|", trim($linea));

        if (count($partes) >= 2) {
            $usuarioTemp = trim($partes[0]);
            $expiraTemp = intval(trim($partes[1]));

            if ($usuarioTemp === $userClean) {

                if ($expiraTemp <= time()) {
                    echo "Not exist";
                    exit;
                }

                echo "TEMP|" . $expiraTemp;
                exit;
            }
        }
    }
}

/*
 * USUARIO NORMAL POR CHAGE
 */
$cmd = "chage -l $usuario | grep 'Account expires'";
$datos = shell_exec($cmd);

if (!$datos) {
    echo "Not exist";
    exit;
}

$fecha = explode(':', $datos);

if (!isset($fecha[1])) {
    echo "Not exist";
    exit;
}

$rawDate = trim($fecha[1]);

if (strtolower($rawDate) == "never") {
    echo "31122099";
    exit;
}

$date = date_create($rawDate);

if (!$date) {
    echo "Not exist";
    exit;
}

$expTime = $date->getTimestamp();

if (time() > $expTime) {
    echo "Not exist";
    exit;
}

echo date_format($date, $FORMATO);
exit;

?>
EOF

cat > "$RUTA/router.php" <<'EOF'
<?php
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

if ($uri === '/' || $uri === '') {
    echo "API VPS PRO OK";
    return;
}

if ($uri === '/api.php') {
    require __DIR__ . '/api.php';
    return;
}

if ($uri === '/checkUser' || $uri === '/checkUser.php' || $uri === '/index.php') {
    require __DIR__ . '/checkUser.php';
    return;
}

return false;
EOF

chmod -R 755 "$RUTA"

# Sudoers opcional, aunque el servicio corre como root.
if ! grep -q "www-data ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

cat > "/etc/systemd/system/$SERVICIO.service" <<EOF
[Unit]
Description=API VPS PRO + CheckUser
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO $RUTA/router.php
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICIO"
systemctl restart "$SERVICIO"

ufw allow "$PUERTO/tcp" 2>/dev/null

echo ""
echo "✅ API VPS PRO + CHECKUSER INSTALADA CORRECTAMENTE"
echo "🌐 API:       http://IP_VPS:$PUERTO/api.php"
echo "🌐 CheckUser: http://IP_VPS:$PUERTO/checkUser"
echo ""
echo "👉 PRUEBA API:"
echo "curl http://127.0.0.1:$PUERTO/api.php"
echo ""
echo "👉 PRUEBA CHECKUSER:"
echo "curl -s -X POST http://127.0.0.1:$PUERTO/checkUser -H 'Content-Type: application/json' -d '{\"user\":\"USUARIO\"}'"
echo ""
