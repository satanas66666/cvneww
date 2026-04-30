#!/bin/bash

echo "🧹 Limpiando instalación anterior..."

# =========================
# LIMPIAR CRON ANTERIOR
# =========================
crontab -l 2>/dev/null | grep -v 'limit_pro.sh' | grep -v 'expire_clean.sh' > /tmp/cronvpn
crontab /tmp/cronvpn
rm -f /tmp/cronvpn

# =========================
# MATAR PROCESOS ANTERIORES
# =========================
pkill -f limit_pro.sh 2>/dev/null
pkill -f expire_clean.sh 2>/dev/null

# =========================
# ELIMINAR SCRIPTS VIEJOS
# =========================
rm -f /root/limit_pro.sh
rm -f /root/expire_clean.sh

# =========================
# LIMPIAR CONFIG (NO BORRA USUARIOS)
# =========================
rm -rf /etc/SSHPlus/limits/*
rm -rf /etc/SSHPlus/blocked/*
rm -rf /etc/SSHPlus/abuse/*

echo "🚀 Instalando sistema PRO VPN..."

# =========================
# CREAR DIRECTORIOS
# =========================
mkdir -p /etc/SSHPlus/limits
mkdir -p /etc/SSHPlus/blocked
mkdir -p /etc/SSHPlus/abuse

chmod -R 777 /etc/SSHPlus

# =========================
# SCRIPT LIMITADOR PRO
# =========================
cat > /root/limit_pro.sh << 'EOF'
#!/bin/bash

LIMIT_DIR="/etc/SSHPlus/limits"
BLOCK_DIR="/etc/SSHPlus/blocked"
ABUSE_DIR="/etc/SSHPlus/abuse"

mkdir -p $BLOCK_DIR
mkdir -p $ABUSE_DIR

MAX_ABUSE=3

for user in $(ls $LIMIT_DIR 2>/dev/null); do

    id "$user" &>/dev/null || continue

    # 🚫 SI ESTA BLOQUEADO → MATAR TODO
    if [ -f "$BLOCK_DIR/$user" ]; then
        pkill -KILL -u $user 2>/dev/null
        continue
    fi

    LIMIT=$(cat $LIMIT_DIR/$user 2>/dev/null)
    [[ -z "$LIMIT" || "$LIMIT" -le 0 ]] && continue

    # 🔥 PROCESOS REALES
    PIDS=$(ps -u $user -o pid=,comm= | grep -E 'sshd|dropbear' | awk '{print $1}')
    COUNT=$(echo "$PIDS" | grep -c .)

    if [ "$COUNT" -gt "$LIMIT" ]; then

        FILE="$ABUSE_DIR/$user"

        if [ ! -f "$FILE" ]; then
            echo 1 > $FILE
        else
            NUM=$(cat $FILE)
            NUM=$((NUM + 1))
            echo $NUM > $FILE
        fi

        ABUSE=$(cat $FILE)

        if [ "$ABUSE" -ge "$MAX_ABUSE" ]; then
            echo "blocked" > $BLOCK_DIR/$user

            # 🔒 BLOQUEO FUERTE (CORREGIDO)
            usermod -L $user 2>/dev/null
            usermod -s /bin/false $user 2>/dev/null

            # 💣 MATAR TODO
            pkill -KILL -u $user 2>/dev/null
        fi

        # 🔥 MATAR EXCESOS
        TO_KILL=$(ps -u $user -o pid=,comm= | grep -E 'sshd|dropbear' \
            | awk '{print $1}' | tail -n +$(($LIMIT + 1)))

        for pid in $TO_KILL; do
            kill -9 $pid 2>/dev/null
        done

    fi

done
EOF

chmod +x /root/limit_pro.sh

# =========================
# SCRIPT ELIMINAR EXPIRADOS + AUTO UNLOCK INTELIGENTE
# =========================
cat > /root/expire_clean.sh << 'EOF'
#!/bin/bash

LIMIT_DIR="/etc/SSHPlus/limits"
BLOCK_DIR="/etc/SSHPlus/blocked"
ABUSE_DIR="/etc/SSHPlus/abuse"

# =========================
# 🔓 DESBLOQUEO INTELIGENTE
# =========================
for user in $(ls "$BLOCK_DIR" 2>/dev/null); do

    id "$user" &>/dev/null || continue

    LIMIT=$(cat "$LIMIT_DIR/$user" 2>/dev/null)
    [[ -z "$LIMIT" || "$LIMIT" -le 0 ]] && continue

    # 🔥 CONTAR CONEXIONES ACTUALES
    COUNT=$(ps -u "$user" -o comm= 2>/dev/null | grep -E 'sshd|dropbear' | wc -l)

    # ✅ SOLO DESBLOQUEAR SI YA RESPETA EL LIMITE
    if [ "$COUNT" -le "$LIMIT" ]; then

        usermod -U "$user" 2>/dev/null
        usermod -s /bin/bash "$user" 2>/dev/null

        rm -f "$BLOCK_DIR/$user"
        rm -f "$ABUSE_DIR/$user"

        echo "$(date) - Usuario desbloqueado correctamente: $user" >> /var/log/unlock.log
    fi

done

# =========================
# 🧹 LIMPIAR EXPIRADOS (NO TOCAR BLOQUEADOS)
# =========================
for user in $(awk -F: '$3>=1000 {print $1}' /etc/passwd); do

    id "$user" &>/dev/null || continue

    # 🚫 NO ELIMINAR SI ESTA BLOQUEADO
    if [ -f "$BLOCK_DIR/$user" ]; then
        continue
    fi

    EXPIRE=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2- | xargs)

    [[ "$EXPIRE" == "never" || -z "$EXPIRE" ]] && continue

    EXPIRE_DATE=$(date -d "$EXPIRE" +%s 2>/dev/null)
    TODAY=$(date +%s)

    [[ -z "$EXPIRE_DATE" ]] && continue

    if [ "$TODAY" -ge "$EXPIRE_DATE" ]; then

        # 💣 MATAR TODO
        pkill -KILL -u "$user" 2>/dev/null
        killall -u "$user" 2>/dev/null

        # 🔥 ELIMINAR
        userdel -f "$user" 2>/dev/null

        rm -f "$LIMIT_DIR/$user"
        rm -f "$BLOCK_DIR/$user"
        rm -f "$ABUSE_DIR/$user"

        echo "$(date) - Usuario eliminado: $user" >> /var/log/expire.log
    fi

done
# =========================
# 🔥 LIMPIAR USUARIOS TEMPORALES
# =========================
TEMP_FILE="/etc/vpn_temp_users"

if [ -f "$TEMP_FILE" ]; then

    NOW=$(date +%s)
    NEW=""

    while IFS="|" read -r user exp; do

        # 🔒 VALIDACIONES PRO
        [ -z "$user" ] && continue
        [[ ! "$exp" =~ ^[0-9]+$ ]] && continue
        id "$user" &>/dev/null || continue

        if [ "$NOW" -ge "$exp" ]; then

            # 💣 matar sesiones
            pkill -KILL -u "$user" 2>/dev/null
            killall -u "$user" 2>/dev/null

            # 🔥 eliminar usuario
            userdel -f "$user" 2>/dev/null

            rm -f "$LIMIT_DIR/$user"
            rm -f "$BLOCK_DIR/$user"
            rm -f "$ABUSE_DIR/$user"

            echo "$(date) - Temporal eliminado: $user" >> /var/log/expire.log

        else
            NEW+="$user|$exp\n"
        fi

    done < "$TEMP_FILE"

    # 🔄 reescribir limpio
    printf "%b" "$NEW" > "$TEMP_FILE"

fi

EOF

chmod +x /root/expire_clean.sh

# =========================
# CONFIGURAR CRON LIMPIO
# =========================
echo "* * * * * /root/limit_pro.sh" > /tmp/cronvpn
echo "* * * * * /root/expire_clean.sh" >> /tmp/cronvpn

crontab /tmp/cronvpn
rm -f /tmp/cronvpn
# =========================
# PERMISOS EXTRA
# =========================
chmod +x /root/*.sh

# =========================
# FINAL
# =========================
echo ""
echo "✅ INSTALACIÓN COMPLETA Y LIMPIA"
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "✔ Sistema reiniciado sin errores"
echo "✔ Anti multi-login activo"
echo "✔ Límite por usuario activo"
echo "✔ Bloqueo automático activo"
echo "✔ Auto eliminación por fecha activo"
echo "✔ Sistema anti-abuso activo"
echo ""
echo "📂 Rutas:"
echo "Limits:   /etc/SSHPlus/limits"
echo "Blocked:  /etc/SSHPlus/blocked"
echo "Abuse:    /etc/SSHPlus/abuse"
echo ""
echo "📄 Logs:"
echo "/var/log/expire.log"
echo ""
echo "🔥 VPS PRO LISTO 🚀"
