#!/bin/bash

echo "🧹 Preparando sistema PRO VPN..."

# =========================
# CONFIGURACIÓN GENERAL
# =========================
LIMIT_DIR="/etc/SSHPlus/limits"
BLOCK_DIR="/etc/SSHPlus/blocked"
ABUSE_DIR="/etc/SSHPlus/abuse"
WARN_DIR="/etc/SSHPlus/warnings"
TEMP_BLOCK_DIR="/etc/SSHPlus/temp_block"
LOG_EXPIRE="/var/log/expire.log"
LOG_ABUSE="/var/log/abuse.log"
LOG_UNLOCK="/var/log/unlock.log"

# =========================
# NO BORRAR DATOS DEL PANEL
# =========================
mkdir -p "$LIMIT_DIR" "$BLOCK_DIR" "$ABUSE_DIR" "$WARN_DIR" "$TEMP_BLOCK_DIR"
touch "$LOG_EXPIRE" "$LOG_ABUSE" "$LOG_UNLOCK" /etc/vpn_temp_users

chmod 755 /etc/SSHPlus
chmod 755 "$LIMIT_DIR" "$BLOCK_DIR" "$ABUSE_DIR" "$WARN_DIR" "$TEMP_BLOCK_DIR"
chmod 644 "$LOG_EXPIRE" "$LOG_ABUSE" "$LOG_UNLOCK"

# =========================
# LIMPIAR CRON ANTERIOR SOLO DE ESTOS SCRIPTS
# =========================
crontab -l 2>/dev/null | grep -v '/root/limit_pro.sh' | grep -v '/root/expire_clean.sh' > /tmp/cronvpn
crontab /tmp/cronvpn
rm -f /tmp/cronvpn

# =========================
# MATAR PROCESOS ANTERIORES
# =========================
pkill -f "/root/limit_pro.sh" 2>/dev/null
pkill -f "/root/expire_clean.sh" 2>/dev/null
pkill -f "/root/expire_daemon.sh" 2>/dev/null

# =========================
# ELIMINAR SCRIPTS VIEJOS
# =========================
rm -f /root/limit_pro.sh
rm -f /root/expire_clean.sh
rm -f /root/expire_daemon.sh

echo "🚀 Instalando sistema PRO VPN profesional..."

# =========================
# SCRIPT LIMITADOR PRO
# =========================
cat > /root/limit_pro.sh << 'EOF'
#!/bin/bash

LIMIT_DIR="/etc/SSHPlus/limits"
BLOCK_DIR="/etc/SSHPlus/blocked"
ABUSE_DIR="/etc/SSHPlus/abuse"
WARN_DIR="/etc/SSHPlus/warnings"
TEMP_BLOCK_DIR="/etc/SSHPlus/temp_block"

LOG_ABUSE="/var/log/abuse.log"

mkdir -p "$LIMIT_DIR" "$BLOCK_DIR" "$ABUSE_DIR" "$WARN_DIR" "$TEMP_BLOCK_DIR"
touch "$LOG_ABUSE"

# =========================
# REGLAS PROFESIONALES
# =========================
# 1 abuso  = advertencia 1
# 2 abusos = advertencia 2
# 3 abusos = bloqueo temporal 10 minutos
# 4 abusos = bloqueo temporal 30 minutos
# 5 abusos = bloqueo temporal 60 minutos
# 6 abusos = bloqueo permanente
MAX_ABUSE_PERMANENT=6

safe_user() {
    echo "$1" | grep -Eq '^[a-zA-Z0-9._-]+$'
}

kill_user_sessions() {
    local user="$1"
    pkill -KILL -u "$user" 2>/dev/null
    killall -u "$user" 2>/dev/null
}

get_user_pids() {
    local user="$1"
    ps -u "$user" -o pid=,comm= 2>/dev/null | grep -E 'sshd|dropbear' | awk '{print $1}'
}

for user in $(ls "$LIMIT_DIR" 2>/dev/null); do

    safe_user "$user" || continue
    id "$user" &>/dev/null || continue

    LIMIT=$(cat "$LIMIT_DIR/$user" 2>/dev/null | tr -dc '0-9')
    [[ -z "$LIMIT" || "$LIMIT" -le 0 ]] && continue

    # =========================
    # BLOQUEO PERMANENTE MANUAL
    # =========================
    if [ -f "$BLOCK_DIR/$user" ]; then
        kill_user_sessions "$user"
        continue
    fi

    # =========================
    # BLOQUEO TEMPORAL ACTIVO
    # =========================
    if [ -f "$TEMP_BLOCK_DIR/$user" ]; then
        UNLOCK_TIME=$(cat "$TEMP_BLOCK_DIR/$user" 2>/dev/null | tr -dc '0-9')
        NOW=$(date +%s)

        if [[ -n "$UNLOCK_TIME" && "$NOW" -lt "$UNLOCK_TIME" ]]; then
            usermod -L "$user" 2>/dev/null
            usermod -s /bin/false "$user" 2>/dev/null
            kill_user_sessions "$user"
            continue
        fi
    fi

    # =========================
    # CONTAR CONEXIONES SSH/DROPBEAR
    # =========================
    PIDS=$(get_user_pids "$user")
    COUNT=$(echo "$PIDS" | grep -c .)

    if [ "$COUNT" -gt "$LIMIT" ]; then

        FILE="$ABUSE_DIR/$user"

        if [ ! -f "$FILE" ]; then
            echo 1 > "$FILE"
        else
            NUM=$(cat "$FILE" 2>/dev/null | tr -dc '0-9')
            [[ -z "$NUM" ]] && NUM=0
            NUM=$((NUM + 1))
            echo "$NUM" > "$FILE"
        fi

        ABUSE=$(cat "$FILE" 2>/dev/null | tr -dc '0-9')
        [[ -z "$ABUSE" ]] && ABUSE=1

        echo "$ABUSE" > "$WARN_DIR/$user"

        echo "$(date '+%F %T') - Abuso detectado: $user conexiones=$COUNT limite=$LIMIT abuso=$ABUSE" >> "$LOG_ABUSE"

        # =========================
        # BLOQUEO PROFESIONAL
        # =========================
        if [ "$ABUSE" -ge "$MAX_ABUSE_PERMANENT" ]; then

            echo "blocked" > "$BLOCK_DIR/$user"
            rm -f "$TEMP_BLOCK_DIR/$user"

            usermod -L "$user" 2>/dev/null
            usermod -s /bin/false "$user" 2>/dev/null
            kill_user_sessions "$user"

            echo "$(date '+%F %T') - Bloqueo permanente por reincidencia: $user" >> "$LOG_ABUSE"

        elif [ "$ABUSE" -ge 5 ]; then

            UNLOCK_TIME=$(( $(date +%s) + 3600 ))
            echo "$UNLOCK_TIME" > "$TEMP_BLOCK_DIR/$user"

            usermod -L "$user" 2>/dev/null
            usermod -s /bin/false "$user" 2>/dev/null
            kill_user_sessions "$user"

            echo "$(date '+%F %T') - Bloqueo temporal 60 minutos: $user" >> "$LOG_ABUSE"

        elif [ "$ABUSE" -ge 4 ]; then

            UNLOCK_TIME=$(( $(date +%s) + 1800 ))
            echo "$UNLOCK_TIME" > "$TEMP_BLOCK_DIR/$user"

            usermod -L "$user" 2>/dev/null
            usermod -s /bin/false "$user" 2>/dev/null
            kill_user_sessions "$user"

            echo "$(date '+%F %T') - Bloqueo temporal 30 minutos: $user" >> "$LOG_ABUSE"

        elif [ "$ABUSE" -ge 3 ]; then

            UNLOCK_TIME=$(( $(date +%s) + 600 ))
            echo "$UNLOCK_TIME" > "$TEMP_BLOCK_DIR/$user"

            usermod -L "$user" 2>/dev/null
            usermod -s /bin/false "$user" 2>/dev/null
            kill_user_sessions "$user"

            echo "$(date '+%F %T') - Bloqueo temporal 10 minutos: $user" >> "$LOG_ABUSE"

        fi

        # =========================
        # MATAR SOLO EXCESOS SI NO FUE BLOQUEADO
        # =========================
        if [ ! -f "$TEMP_BLOCK_DIR/$user" ] && [ ! -f "$BLOCK_DIR/$user" ]; then
            TO_KILL=$(get_user_pids "$user" | tail -n +$((LIMIT + 1)))

            for pid in $TO_KILL; do
                kill -9 "$pid" 2>/dev/null
            done
        fi
    fi

done
EOF

chmod +x /root/limit_pro.sh

# =========================
# SCRIPT ELIMINAR EXPIRADOS + AUTO UNLOCK
# =========================
cat > /root/expire_clean.sh << 'EOF'
#!/bin/bash

LIMIT_DIR="/etc/SSHPlus/limits"
BLOCK_DIR="/etc/SSHPlus/blocked"
ABUSE_DIR="/etc/SSHPlus/abuse"
WARN_DIR="/etc/SSHPlus/warnings"
TEMP_BLOCK_DIR="/etc/SSHPlus/temp_block"

TEMP_FILE="/etc/vpn_temp_users"

LOG_EXPIRE="/var/log/expire.log"
LOG_UNLOCK="/var/log/unlock.log"

mkdir -p "$LIMIT_DIR" "$BLOCK_DIR" "$ABUSE_DIR" "$WARN_DIR" "$TEMP_BLOCK_DIR"
touch "$TEMP_FILE" "$LOG_EXPIRE" "$LOG_UNLOCK"

safe_user() {
    echo "$1" | grep -Eq '^[a-zA-Z0-9._-]+$'
}

kill_user_sessions() {
    local user="$1"
    pkill -KILL -u "$user" 2>/dev/null
    killall -u "$user" 2>/dev/null
}

remove_user_files() {
    local user="$1"
    rm -f "$LIMIT_DIR/$user"
    rm -f "$BLOCK_DIR/$user"
    rm -f "$ABUSE_DIR/$user"
    rm -f "$WARN_DIR/$user"
    rm -f "$TEMP_BLOCK_DIR/$user"
    rm -f "$ABUSE_DIR/${user}_temp_count"
}

# =========================
# DESBLOQUEO TEMPORAL AUTOMÁTICO
# =========================
NOW=$(date +%s)

for user in $(ls "$TEMP_BLOCK_DIR" 2>/dev/null); do

    safe_user "$user" || continue
    id "$user" &>/dev/null || {
        rm -f "$TEMP_BLOCK_DIR/$user"
        continue
    }

    # Si está bloqueado permanente/manual, no desbloquear.
    [ -f "$BLOCK_DIR/$user" ] && continue

    UNLOCK_TIME=$(cat "$TEMP_BLOCK_DIR/$user" 2>/dev/null | tr -dc '0-9')

    if [[ -n "$UNLOCK_TIME" && "$NOW" -ge "$UNLOCK_TIME" ]]; then

        usermod -U "$user" 2>/dev/null
        usermod -s /bin/bash "$user" 2>/dev/null

        rm -f "$TEMP_BLOCK_DIR/$user"

        echo "$(date '+%F %T') - Desbloqueo automático temporal: $user" >> "$LOG_UNLOCK"
    fi

done

# =========================
# LIMPIAR USUARIOS NORMALES VENCIDOS
# =========================
for user in $(awk -F: '$3>=1000 {print $1}' /etc/passwd); do

    safe_user "$user" || continue
    id "$user" &>/dev/null || continue

    # No eliminar bloqueados permanentes/manuales
    if [ -f "$BLOCK_DIR/$user" ]; then
        continue
    fi

    # Si es temporal, lo procesa la sección temporal
    if grep -q "^$user|" "$TEMP_FILE" 2>/dev/null; then
        continue
    fi

    EXPIRE=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2- | xargs)

    [[ "$EXPIRE" == "never" || -z "$EXPIRE" ]] && continue

    EXPIRE_DATE=$(date -d "$EXPIRE" +%s 2>/dev/null)
    TODAY=$(date +%s)

    [[ -z "$EXPIRE_DATE" ]] && continue

    if [ "$TODAY" -ge "$EXPIRE_DATE" ]; then

        kill_user_sessions "$user"
        userdel -f "$user" 2>/dev/null

        remove_user_files "$user"

        echo "$(date '+%F %T') - Usuario normal eliminado por fecha: $user" >> "$LOG_EXPIRE"
    fi

done

# =========================
# LIMPIAR USUARIOS TEMPORALES
# =========================
if [ -f "$TEMP_FILE" ]; then

    NOW=$(date +%s)
    NEW=""

    while IFS="|" read -r user exp || [ -n "$user" ]; do

        user="$(echo "$user" | xargs)"
        exp="$(echo "$exp" | xargs)"

        [ -z "$user" ] && continue
        safe_user "$user" || continue
        [[ ! "$exp" =~ ^[0-9]+$ ]] && continue

        # Si el usuario ya no existe, no guardar la línea
        if ! id "$user" &>/dev/null; then
            continue
        fi

        if [ "$NOW" -ge "$exp" ]; then

            kill_user_sessions "$user"
            userdel -f "$user" 2>/dev/null

            remove_user_files "$user"

            echo "$(date '+%F %T') - Usuario temporal eliminado: $user" >> "$LOG_EXPIRE"

        else
            NEW+="$user|$exp\n"
        fi

    done < "$TEMP_FILE"

    printf "%b" "$NEW" > "$TEMP_FILE"
fi
EOF

chmod +x /root/expire_clean.sh

# =========================
# CREAR DAEMON AUTOMÁTICO
# =========================
echo "⚙️ Configurando daemon de expiración..."

systemctl stop expire-daemon 2>/dev/null
systemctl disable expire-daemon 2>/dev/null
rm -f /etc/systemd/system/expire-daemon.service

cat > /root/expire_daemon.sh << 'EOF'
#!/bin/bash

while true; do
    bash /root/expire_clean.sh >/dev/null 2>&1
    sleep 5
done
EOF

chmod +x /root/expire_daemon.sh

cat > /etc/systemd/system/expire-daemon.service <<EOF
[Unit]
Description=Expire Users Daemon PRO
After=network.target

[Service]
ExecStart=/bin/bash /root/expire_daemon.sh
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable expire-daemon
systemctl restart expire-daemon

echo "✅ Daemon activo: eliminación/desbloqueo cada 5s"

# =========================
# CONFIGURAR CRON SIN BORRAR OTROS CRON
# =========================
crontab -l 2>/dev/null | grep -v '/root/limit_pro.sh' > /tmp/cronvpn
echo "* * * * * /root/limit_pro.sh >/dev/null 2>&1" >> /tmp/cronvpn
crontab /tmp/cronvpn
rm -f /tmp/cronvpn

chmod +x /root/*.sh

# =========================
# FINAL
# =========================
echo ""
echo "✅ INSTALACIÓN COMPLETA Y PROFESIONAL"
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "✔ Sistema reiniciado sin errores"
echo "✔ Anti multi-login activo"
echo "✔ Límite por usuario activo"
echo "✔ Advertencias por abuso activas"
echo "✔ Bloqueo temporal automático activo"
echo "✔ Bloqueo permanente por reincidencia activo"
echo "✔ Auto eliminación por fecha activo"
echo "✔ Auto eliminación temporal activo"
echo "✔ Auto desbloqueo temporal activo"
echo "✔ Sistema anti-abuso activo"
echo ""
echo "📂 Rutas:"
echo "Limits:      /etc/SSHPlus/limits"
echo "Blocked:     /etc/SSHPlus/blocked"
echo "Abuse:       /etc/SSHPlus/abuse"
echo "Warnings:    /etc/SSHPlus/warnings"
echo "TempBlock:   /etc/SSHPlus/temp_block"
echo ""
echo "📄 Logs:"
echo "$LOG_EXPIRE"
echo "$LOG_ABUSE"
echo "$LOG_UNLOCK"
echo ""
echo "🔥 VPS PRO LISTO 🚀"
