#!/bin/bash
# =============================================================================
# Sistema de Ventas — Script de Instalación para Ubuntu Server
# =============================================================================
#
# Prepara un servidor Ubuntu Server 22.04/24.04 LTS e instala todo el stack:
#   - Nginx (reverse proxy + load balancer)
#   - App Node.js x2 (Sistema Ventas con sesiones en Redis)
#   - Redis (session store)
#   - Samba AD DC (Active Directory Domain Controller)
#   - PostgreSQL 17 (primary + replica con replicación streaming)
#   - Backup automático (DB + archivos + rclone cloud sync)
#   - Stack de observabilidad (Prometheus, Grafana, Loki, Promtail)
#
# REQUISITOS MÍNIMOS DE HARDWARE:
#   - 4 vCPU  |  8 GB RAM  |  40 GB disco
#
# REQUISITOS DE SOFTWARE:
#   - Ubuntu Server 22.04 o 24.04 LTS (instalación mínima)
#   - Acceso a internet
#   - Ejecutar como root (o con sudo)
#
# USO:
#   1. Copiá este proyecto al servidor Ubuntu (scp, rsync, git clone)
#   2. Ejecutá como root desde la raíz del proyecto:
#        chmod +x install-ubuntu.sh
#        sudo ./install-ubuntu.sh
#   3. Por defecto vienen activados TLS, Fail2Ban y ClamAV.
#      Para desactivarlos: sudo ENABLE_TLS=0 ... ./install-ubuntu.sh
#      Para DHCP (requiere interfaz host-only): sudo ENABLE_DHCP=1 DHCP_INTERFACE=enp0s8 ...
#   4. Seguí las instrucciones en pantalla
#
# IMPORTANTE:
#   - El script es IDEMPOTENTE: podés ejecutarlo múltiples veces sin miedo
#   - Se saltea pasos ya completados
#   - Si algo falla a la mitad, corregí el problema y volvé a ejecutar
#
# =============================================================================

set -euo pipefail

# ─── Colores ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Configuración ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/docker-compose.env.example"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# Directorios host para datos persistentes
APP_DATA_DIR="${APP_DATA_DIR:-/srv/sistemaventas/app-data}"
BACKUPS_DIR="${BACKUPS_DIR:-/srv/sistemaventas/backups}"
RCLONE_CONFIG_DIR="${RCLONE_CONFIG_DIR:-/srv/sistemaventas/rclone}"
HOST_TLS_DIR="${HOST_TLS_DIR:-/srv/sistemaventas/tls}"

# Features de seguridad y hardening (activadas por defecto)
SKIP_SYSTEM_UPDATE="${SKIP_SYSTEM_UPDATE:-0}"
ENABLE_TLS="${ENABLE_TLS:-1}"
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-1}"
ENABLE_ANTIMALWARE="${ENABLE_ANTIMALWARE:-1}"
# DHCP requiere configurar interfaz — se mantiene opt-in
ENABLE_DHCP="${ENABLE_DHCP:-0}"

# DHCP (solo para red aislada / laboratorio)
DHCP_INTERFACE="${DHCP_INTERFACE:-}"
DHCP_SUBNET="${DHCP_SUBNET:-}"
DHCP_NETMASK="${DHCP_NETMASK:-255.255.255.0}"
DHCP_RANGE_START="${DHCP_RANGE_START:-}"
DHCP_RANGE_END="${DHCP_RANGE_END:-}"
DHCP_GATEWAY="${DHCP_GATEWAY:-}"
DHCP_DNS="${DHCP_DNS:-}"
DHCP_DOMAIN="${DHCP_DOMAIN:-proyecto.local}"

# Fail2Ban
FAIL2BAN_MAXRETRY="${FAIL2BAN_MAXRETRY:-5}"
FAIL2BAN_FINDTIME="${FAIL2BAN_FINDTIME:-10m}"
FAIL2BAN_BANTIME="${FAIL2BAN_BANTIME:-1h}"

# ClamAV
ANTIMALWARE_SCAN_DIRS="${ANTIMALWARE_SCAN_DIRS:-/srv/sistemaventas /var/lib/docker/volumes}"

# TLS
TLS_APP_PORT="${TLS_APP_PORT:-8443}"
TLS_GRAFANA_PORT="${TLS_GRAFANA_PORT:-8444}"
TLS_CERT_CN="${TLS_CERT_CN:-sistemaventas.local}"
TLS_CERT_DAYS="${TLS_CERT_DAYS:-365}"

# ─── Funciones de logging ──────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[✔]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[⚠]${NC}   $*"; }
log_error() { echo -e "${RED}[✘]${NC}  $*"; }
log_step()  { echo -e "\n${CYAN}${BOLD}═══ $* ═══${NC}"; }
log_ask()   { echo -e "${YELLOW}[?]${NC}   $*"; }

is_enabled() {
    case "${1,,}" in
        1|true|yes|on|si|sí|s) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_env_var() {
    local key="$1"
    local value="$2"
    local tmp

    tmp="$(mktemp)"
    if [[ -f "$ENV_FILE" ]]; then
        grep -v "^${key}=" "$ENV_FILE" > "$tmp" || true
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$ENV_FILE"
}

# ─── Banner ────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║       Sistema de Ventas — Instalador para Ubuntu Server          ║"
echo "║                                                                  ║"
echo "║       Docker Compose Stack:                                      ║"
echo "║       Nginx · App (x2) · Redis · PostgreSQL (HA)                 ║"
echo "║       Samba AD DC · Backup · Prometheus · Grafana · Loki        ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# =============================================================================
# 0. VERIFICACIONES INICIALES
# =============================================================================
log_step "PASO 0: Verificaciones iniciales"

# 0.1 — Root check
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root."
   echo "       Ejecutalo con:  sudo ./install-ubuntu.sh"
   exit 1
fi
log_ok "Ejecutando como root"

# 0.2 — Detectar Ubuntu
if [[ -f /etc/os-release ]]; then
    source /etc/os-release 2>/dev/null || true
    if [[ "$ID" == "ubuntu" ]]; then
        log_ok "Sistema: ${PRETTY_NAME:-Ubuntu} (${VERSION_CODENAME:-unknown})"
    else
        log_warn "Se detectó ${PRETTY_NAME:-otro SO}, no Ubuntu."
        log_warn "El script está diseñado para Ubuntu Server 22.04/24.04."

        if [[ -t 0 ]]; then
            echo ""
            log_ask "¿Continuar de todas formas? [s/N] "
            read -r RESP || true
            if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
                log_info "Saliendo."
                exit 0
            fi
        else
            log_info "Ejecución no interactiva — continuando de todas formas"
        fi
    fi
else
    log_warn "No se pudo detectar el sistema operativo."
fi

# 0.3 — Verificar que estamos en el directorio del proyecto
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "No se encontró docker-compose.yml en $PROJECT_DIR"
    log_error "Ejecutá este script desde la raíz del proyecto."
    exit 1
fi
log_ok "Directorio del proyecto: $PROJECT_DIR"

# 0.4 — Verificar recursos del sistema
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
CPU_COUNT=$(nproc)
DISK_FREE_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}')
[[ -z "$DISK_FREE_GB" ]] && DISK_FREE_GB=99

echo ""
log_info "Recursos detectados:"
log_info "  CPU:     ${CPU_COUNT} vCPUs"
log_info "  RAM:     ${TOTAL_RAM_GB} GB"
log_info "  Disco /: ${DISK_FREE_GB} GB libres"

if [[ $TOTAL_RAM_GB -lt 4 ]]; then
    log_warn "RAM baja (< 4 GB). El stack puede volverse inestable. Se recomienda swap."
fi
if [[ $CPU_COUNT -lt 2 ]]; then
    log_warn "Pocos CPUs (< 2). Los tiempos de inicio serán lentos."
fi
if [[ $DISK_FREE_GB -lt 10 ]]; then
    log_warn "MUY poco espacio en disco (< 10 GB). Los backups pueden llenarlo en días."
    log_warn "Ajustá DB_BACKUP_RETENTION_DAYS=1 y FILES_BACKUP_RETENTION_DAYS=1 en .env"
fi

echo ""
log_ok "Verificaciones iniciales completadas."

# =============================================================================
# 1. ACTUALIZAR SISTEMA (se puede skipear)
# =============================================================================

if is_enabled "$SKIP_SYSTEM_UPDATE"; then
    log_warn "PASO 1: System update SKIPPED (SKIP_SYSTEM_UPDATE=1)"
else
    log_step "PASO 1: Actualizando paquetes del sistema"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y || log_warn "System upgrade failed — continuing anyway"
    log_ok "Sistema actualizado"
fi

# =============================================================================
# 2. INSTALAR PREREQUISITOS (solo lo que falta)
# =============================================================================
log_step "PASO 2: Verificando prerequisitos"

MISSING_PKGS=""
for pkg in curl wget git tar gzip openssl ca-certificates; do
    if ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

# Paquetes extra que no son comandos directos
for pkg in software-properties-common cron unzip bash-completion; do
    dpkg -s "$pkg" &>/dev/null || MISSING_PKGS="$MISSING_PKGS $pkg"
done

if [[ -n "$(echo $MISSING_PKGS | tr -d ' ')" ]]; then
    log_info "Instalando paquetes faltantes:$MISSING_PKGS"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y $MISSING_PKGS || log_warn "Algunos prerequisitos no se instalaron — puede que igual funcione"
else
    log_ok "Todos los prerequisitos ya están instalados"
fi

# =============================================================================
# 3. INSTALAR DOCKER CE + DOCKER COMPOSE
# =============================================================================
log_step "PASO 3: Instalando Docker Engine y Docker Compose"

# 3.1 — Remover versiones viejas si existen
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" 2>/dev/null || true
done

# 3.2 — Instalar Docker desde el repo oficial (si no está ya)
if ! command -v docker &>/dev/null; then
    log_info "Agregando repositorio oficial de Docker CE..."

    apt-get update -y
    apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y

    log_info "Instalando Docker CE + Docker Compose plugin..."
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_ok "Docker instalado"
else
    log_ok "Docker ya está instalado: $(docker --version)"
fi

# 3.3 — Agregar usuario al grupo docker (para no usar sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    log_info "Usuario $SUDO_USER agregado al grupo docker (requiere re-login)"
fi

# 3.4 — Iniciar y habilitar Docker
systemctl enable --now docker
if systemctl is-active --quiet docker; then
    log_ok "Docker está corriendo"
else
    log_error "Docker no pudo iniciarse. Revisá: systemctl status docker"
    exit 1
fi

# 3.5 — Verificar Docker Compose
if docker compose version &>/dev/null; then
    log_ok "Docker Compose: $(docker compose version)"
else
    log_error "Docker Compose no está disponible. ¿Instalaste docker-compose-plugin?"
    exit 1
fi

# =============================================================================
# 4. CONFIGURAR DAEMON DOCKER (log rotation, storage driver)
# =============================================================================
log_step "PASO 4: Configurando Docker daemon"

mkdir -p /etc/docker
DAEMON_JSON="/etc/docker/daemon.json"

if [[ ! -f "$DAEMON_JSON" ]]; then
    cat > "$DAEMON_JSON" <<'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
DAEMON
    log_info "Creado $DAEMON_JSON con log rotation y overlay2"
    systemctl restart docker
    log_ok "Docker reiniciado con nueva configuración"
else
    log_ok "$DAEMON_JSON ya existe — no se modifica"
fi

# =============================================================================
# 5. CONFIGURAR SWAP (esencial si tenés ≤ 8 GB RAM)
# =============================================================================
log_step "PASO 5: Configurando swap"

TOTAL_RAM_GB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
CURRENT_SWAP_GB=$(free -g | awk '/Swap:/ {print $2}')
SWAP_FILE="/swapfile"
SWAP_SIZE_GB=4

if [[ $TOTAL_RAM_GB -le 8 ]]; then
    if [[ ${CURRENT_SWAP_GB:-0} -lt 2 ]]; then
        log_warn "Tenés ${TOTAL_RAM_GB} GB de RAM y ${CURRENT_SWAP_GB:-0} GB de swap."
        log_warn "El stack completo necesita ~5 GB. Sin swap, el kernel va a matar contenedores (OOM)."
        echo ""
        log_info "Creando archivo de swap de ${SWAP_SIZE_GB} GB en ${SWAP_FILE}..."

        if [[ -f "$SWAP_FILE" ]]; then
            log_info "Archivo de swap ya existe. Lo activo y sigo."
            swapon "$SWAP_FILE" 2>/dev/null || true
        else
            dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
            chmod 600 "$SWAP_FILE"
            mkswap "$SWAP_FILE"
            swapon "$SWAP_FILE"

            if ! grep -q "$SWAP_FILE" /etc/fstab; then
                echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
            fi

            sysctl vm.swappiness=20
            echo "vm.swappiness=20" > /etc/sysctl.d/99-swap.conf

            log_ok "Swap de ${SWAP_SIZE_GB} GB configurado y persistente"
        fi
    else
        log_ok "Swap suficiente: ${CURRENT_SWAP_GB} GB"
    fi
else
    log_ok "RAM suficiente (${TOTAL_RAM_GB} GB) — swap no necesario"
fi

# =============================================================================
# 6. CONFIGURAR FIREWALL (ufw)
# =============================================================================
log_step "PASO 6: Configurando firewall (ufw)"

# Asegurar que ufw está instalado
if ! command -v ufw &>/dev/null; then
    apt-get install -y ufw
fi

# Configurar política por defecto
ufw --force default deny incoming
ufw --force default allow outgoing

# SSH (siempre)
ufw allow 22/tcp comment 'SSH' 2>/dev/null || true

# ─── Puertos de la aplicación ───
log_info "Abriendo puertos web..."
ufw allow 8080/tcp comment 'App' 2>/dev/null || true
ufw allow 8081/tcp comment 'Grafana' 2>/dev/null || true

# ─── Puertos de Samba AD DC ───
log_info "Abriendo puertos de Samba AD DC (Active Directory)..."
SAMBA_TCP_PORTS=(53 88 135 389 445 464 636 3268 3269)
SAMBA_UDP_PORTS=(53 88 389 464 123)

for PORT in "${SAMBA_TCP_PORTS[@]}"; do
    ufw allow "${PORT}/tcp" comment "Samba AD" 2>/dev/null || true
done
for PORT in "${SAMBA_UDP_PORTS[@]}"; do
    ufw allow "${PORT}/udp" comment "Samba AD" 2>/dev/null || true
done

# Rango de puertos dinámicos RPC para Samba
ufw allow 50000:50050/tcp comment 'Samba RPC' 2>/dev/null || true

# ─── Activar firewall ───
ufw --force enable
log_ok "Firewall (ufw) configurado"

# ─── Mostrar reglas activas ───
echo ""
log_info "Reglas de firewall activas:"
ufw status numbered 2>/dev/null || true
echo ""

# =============================================================================
# 7. APPARMOR (Ubuntu default — Docker funciona out of the box)
# =============================================================================
log_step "PASO 7: Verificando AppArmor para Docker"

if command -v aa-status &>/dev/null; then
    log_info "AppArmor está activo — Docker lo maneja automáticamente."
    log_ok "No se requieren ajustes manuales (a diferencia de SELinux en RHEL)"
else
    log_info "AppArmor no detectado. Docker usará su propio perfil de seguridad."
fi

# =============================================================================
# 8. CREAR ESTRUCTURA DE DIRECTORIOS
# =============================================================================
log_step "PASO 8: Creando estructura de directorios host"

mkdir -p "$APP_DATA_DIR"
mkdir -p "$BACKUPS_DIR"/{db,files}
mkdir -p "$RCLONE_CONFIG_DIR"
mkdir -p "$HOST_TLS_DIR"

log_ok "Directorios creados:"
log_info "  Datos de app:    $APP_DATA_DIR"
log_info "  Backups:         $BACKUPS_DIR"
log_info "  Rclone config:   $RCLONE_CONFIG_DIR"
log_info "  Certificados:    $HOST_TLS_DIR"

# =============================================================================
# 9. CONFIGURAR ARCHIVO .ENV
# =============================================================================
log_step "PASO 9: Configurando variables de entorno (.env)"

if [[ -f "$ENV_FILE" ]]; then
    log_info "Ya existe un archivo .env. Se mantiene sin cambios."
    log_info "Si querés regenerarlo con los defaults, borralo primero:"
    log_info "  rm $ENV_FILE && sudo ./install-ubuntu.sh"
else
    if [[ -f "$ENV_EXAMPLE" ]]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        log_ok ".env creado desde docker-compose.env.example"
    else
        log_warn "No se encontró docker-compose.env.example. Creando .env con defaults..."
        cat > "$ENV_FILE" <<'ENVEOF'
# =============================================================================
# Sistema de Ventas — Variables de Entorno
# Generado por install-ubuntu.sh
# =============================================================================
# CAMBIÁ todas las contraseñas por defecto antes de usar en producción.
# Después de editar, ejecutá: docker compose up -d
# =============================================================================
# ─── Puertos ───
APP_PORT=8080
GRAFANA_PORT=8081

# ─── PostgreSQL ───
POSTGRES_USER=postgres
POSTGRES_PASSWORD=cambiar_esta_password_ya
POSTGRES_DB=sistemaventas
REPLICATION_USER=replicator
REPLICATION_PASSWORD=cambiar_replication_password_ya

# ─── App ───
SESSION_SECRET=cambiar_este_secreto_ya
FORCE_SECURE_COOKIES=false
TRUST_PROXY=true

# ─── Samba AD DC ───
SAMBA_DOMAIN=proyecto.local
SAMBA_REALM=PROYECTO.LOCAL
SAMBA_WORKGROUP=PROYECTO
SAMBA_NETBIOS_NAME=DC01
SAMBA_DNS_FORWARDER=1.1.1.1
SAMBA_ADMIN_PASSWORD=Admin123!

# ─── Grafana ───
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin123

# ─── Directorios host para datos persistentes ───
HOST_APP_DATA_DIR=/srv/sistemaventas/app-data
HOST_BACKUPS_DIR=/srv/sistemaventas/backups
RCLONE_CONFIG_DIR=/srv/sistemaventas/rclone
HOST_TLS_DIR=/srv/sistemaventas/tls
TLS_APP_PORT=8443
TLS_GRAFANA_PORT=8444

# ─── Backups automáticos ───
DB_BACKUP_INTERVAL_SECONDS=21600
DB_BACKUP_RETENTION_DAYS=7
FILES_BACKUP_INTERVAL_SECONDS=21600
FILES_BACKUP_RETENTION_DAYS=7
FILES_ARCHIVE_PREFIX=app-files

# ─── Rclone (sincronización cloud) ───
RCLONE_REMOTE_NAME=gdrive
RCLONE_REMOTE_PATH=sistemaventas/backups
RCLONE_SYNC_MODE=copy
RCLONE_SYNC_INTERVAL_SECONDS=900
ENVEOF
        log_ok ".env creado con valores por defecto"
    fi

    echo ""
    log_warn "──────────────────────────────────────────────────────────"
    log_warn "  REVISÁ el archivo .env y cambiá las contraseñas por"
    log_warn "  defecto ANTES de levantar el stack en producción."
    log_warn ""
    log_warn "  Variables críticas a cambiar:"
    log_warn "    POSTGRES_PASSWORD"
    log_warn "    REPLICATION_PASSWORD"
    log_warn "    SESSION_SECRET"
    log_warn "    SAMBA_ADMIN_PASSWORD"
    log_warn "    GRAFANA_ADMIN_PASSWORD"
    log_warn "──────────────────────────────────────────────────────────"
    echo ""
fi

ensure_env_var "HOST_APP_DATA_DIR" "$APP_DATA_DIR"
ensure_env_var "HOST_BACKUPS_DIR" "$BACKUPS_DIR"
ensure_env_var "RCLONE_CONFIG_DIR" "$RCLONE_CONFIG_DIR"
ensure_env_var "HOST_TLS_DIR" "$HOST_TLS_DIR"
ensure_env_var "TLS_APP_PORT" "$TLS_APP_PORT"
ensure_env_var "TLS_GRAFANA_PORT" "$TLS_GRAFANA_PORT"
if is_enabled "$ENABLE_TLS"; then
    ensure_env_var "FORCE_SECURE_COOKIES" "true"
else
    ensure_env_var "FORCE_SECURE_COOKIES" "false"
fi
ensure_env_var "TRUST_PROXY" "true"

# =============================================================================
# 10. CONFIGURAR FAIL2BAN (opcional)
# =============================================================================
if is_enabled "$ENABLE_FAIL2BAN"; then
    log_step "PASO 10: Configurando Fail2Ban para SSH"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y fail2ban
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sistemaventas-sshd.local <<EOF
[DEFAULT]
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
banaction = ufw
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
EOF
    systemctl enable --now fail2ban
    fail2ban-client status sshd 2>/dev/null || true
    log_ok "Fail2Ban configurado para proteger SSH"
else
    log_info "Fail2Ban omitido (ENABLE_FAIL2BAN=0)"
fi

# =============================================================================
# 11. CONFIGURAR ANTIMALWARE (opcional)
# =============================================================================
if is_enabled "$ENABLE_ANTIMALWARE"; then
    log_step "PASO 11: Configurando antimalware ClamAV"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y clamav clamav-freshclam
    systemctl stop clamav-freshclam 2>/dev/null || true
    freshclam || log_warn "freshclam no pudo actualizar firmas ahora mismo; revisalo luego"
    cat > /etc/cron.d/sistemaventas-clamav <<EOF
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
15 2 * * * root freshclam --quiet && clamscan -ri --log=/var/log/clamav/sistemaventas-scan.log ${ANTIMALWARE_SCAN_DIRS}
EOF
    systemctl enable --now cron
    log_ok "ClamAV configurado con actualización y escaneo diario"
else
    log_info "Antimalware omitido (ENABLE_ANTIMALWARE=0)"
fi

# =============================================================================
# 12. CONFIGURAR DHCP (opcional, solo red aislada)
# =============================================================================
if is_enabled "$ENABLE_DHCP"; then
    log_step "PASO 12: Configurando DHCP para laboratorio aislado"
    if [[ -z "$DHCP_INTERFACE" || -z "$DHCP_SUBNET" || -z "$DHCP_RANGE_START" || -z "$DHCP_RANGE_END" ]]; then
        log_error "Para ENABLE_DHCP=1 necesitás definir DHCP_INTERFACE, DHCP_SUBNET, DHCP_RANGE_START y DHCP_RANGE_END"
        exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y isc-dhcp-server

    DHCP_SERVER_IP=$(ip -4 -o addr show dev "$DHCP_INTERFACE" | awk '{split($4,a,"/"); print a[1]}' | head -1)
    DHCP_DNS_VALUE="$DHCP_DNS"
    if [[ -z "$DHCP_DNS_VALUE" ]]; then
        DHCP_DNS_VALUE="${DHCP_SERVER_IP:-1.1.1.1}"
    fi

    cat > /etc/dhcp/dhcpd.conf <<EOF
authoritative;
default-lease-time 600;
max-lease-time 7200;
option domain-name "${DHCP_DOMAIN}";
option domain-name-servers ${DHCP_DNS_VALUE};

subnet ${DHCP_SUBNET} netmask ${DHCP_NETMASK} {
  range ${DHCP_RANGE_START} ${DHCP_RANGE_END};
  option subnet-mask ${DHCP_NETMASK};
EOF
    if [[ -n "$DHCP_GATEWAY" ]]; then
        echo "  option routers ${DHCP_GATEWAY};" >> /etc/dhcp/dhcpd.conf
    fi
    echo "}" >> /etc/dhcp/dhcpd.conf

    cat > /etc/default/isc-dhcp-server <<EOF
INTERFACESv4="${DHCP_INTERFACE}"
INTERFACESv6=""
EOF

    ufw allow 67/udp comment 'DHCP' 2>/dev/null || true
    systemctl enable --now isc-dhcp-server
    log_warn "DHCP habilitado. Usalo SOLO en red aislada / host-only / laboratorio."
    log_ok "DHCP configurado sobre interfaz ${DHCP_INTERFACE}"
else
    log_info "DHCP omitido (ENABLE_DHCP=0)"
fi

# =============================================================================
# 13. CONFIGURAR TLS/HTTPS (opcional)
# =============================================================================
mkdir -p "$PROJECT_DIR/nginx/conf.d"
mkdir -p "$HOST_TLS_DIR"
if is_enabled "$ENABLE_TLS"; then
    log_step "PASO 13: Configurando TLS para Nginx"

    if ! command -v openssl &>/dev/null; then
        log_warn "openssl no encontrado — instalando..."
        apt-get install -y openssl
    fi

    if [[ ! -f "$HOST_TLS_DIR/fullchain.pem" || ! -f "$HOST_TLS_DIR/privkey.pem" ]]; then
        log_info "Generando certificado autofirmado (${TLS_CERT_DAYS} días)..."
        if openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$HOST_TLS_DIR/privkey.pem" \
            -out "$HOST_TLS_DIR/fullchain.pem" \
            -days "$TLS_CERT_DAYS" \
            -subj "/CN=${TLS_CERT_CN}" 2>/dev/null; then
            chmod 600 "$HOST_TLS_DIR/privkey.pem"
            chmod 644 "$HOST_TLS_DIR/fullchain.pem"
            log_ok "Certificado autofirmado generado en $HOST_TLS_DIR"
        else
            log_error "Fallo al generar certificado TLS. Revisá permisos en $HOST_TLS_DIR"
            exit 1
        fi
    else
        log_ok "Ya existen certificados TLS en $HOST_TLS_DIR — se reutilizan"
    fi

    cat > "$PROJECT_DIR/nginx/conf.d/https.conf" <<'EOF'
server {
  listen 443 ssl;
  server_name _;

  ssl_certificate /etc/nginx/certs/fullchain.pem;
  ssl_certificate_key /etc/nginx/certs/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;

  location /health {
    access_log off;
    return 200 'ok';
    add_header Content-Type text/plain;
  }

  location / {
    proxy_pass http://sistemaventas_backend;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Connection "";
  }
}

server {
  listen 444 ssl;
  server_name _;

  ssl_certificate /etc/nginx/certs/fullchain.pem;
  ssl_certificate_key /etc/nginx/certs/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;

  location /health {
    access_log off;
    return 200 'ok';
    add_header Content-Type text/plain;
  }

  location / {
    proxy_pass http://grafana:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Connection "";
  }
}
EOF

    ufw allow "${TLS_APP_PORT}/tcp" comment 'App HTTPS' 2>/dev/null || true
    ufw allow "${TLS_GRAFANA_PORT}/tcp" comment 'Grafana HTTPS' 2>/dev/null || true
    log_ok "TLS/HTTPS configurado para aplicación y Grafana"
else
    cat > "$PROJECT_DIR/nginx/conf.d/https.conf" <<'EOF'
# TLS opcional deshabilitado.
# install-ubuntu.sh reemplaza este archivo cuando ENABLE_TLS=1.
EOF
    log_info "TLS omitido (ENABLE_TLS=0)"
fi

# =============================================================================
# 14. PULL DE IMÁGENES DOCKER
# =============================================================================
log_step "PASO 14: Descargando imágenes Docker"

log_info "Esto puede tardar varios minutos la primera vez..."
cd "$PROJECT_DIR"

log_info "Descargando imágenes Docker..."
set +e
docker compose pull 2>&1
PULL_EXIT=$?
set -e
if [[ $PULL_EXIT -ne 0 ]]; then
    log_warn "Algunas imágenes no se pudieron descargar (red, rate limit de Docker Hub, etc.)"
    log_warn "No te preocupes — se reintentará automáticamente al hacer docker compose up."
fi

# Build de la app local
log_info "Construyendo imagen de la aplicación (sistemaventas)..."
if [[ -f sistemaventas/package.json ]]; then
    set +e
    docker compose build app1 2>&1
    BUILD_EXIT=$?
    set -e
    if [[ $BUILD_EXIT -ne 0 ]]; then
        log_warn "Build de la app falló. Posibles causas:"
        log_warn "  - npm ci falló (problema de red o package.json corrupto)"
        log_warn "  - Dockerfile tiene errores"
        log_warn "El resto del stack se puede levantar igual. Revisá los logs luego."
    else
        log_ok "App construida correctamente"
    fi
else
    log_warn "No se encontró sistemaventas/package.json — ¿clonaste el repo completo?"
    log_warn "La app no se va a construir. El resto del stack sí puede levantar."
fi

log_ok "Descarga de imágenes completada (con o sin warnings, seguimos)"

# =============================================================================
# 15. VALIDAR CONFIGURACIÓN DE DOCKER COMPOSE
# =============================================================================
log_step "PASO 15: Validando docker-compose.yml"

log_info "Validando docker-compose.yml + override..."

set +e
COMPOSE_OUTPUT=$(docker compose config 2>&1)
COMPOSE_EXIT=$?
set -e

if [[ $COMPOSE_EXIT -eq 0 ]]; then
    log_ok "Configuración de Docker Compose válida"
else
    log_warn "docker compose config encontró problemas:"
    echo ""
    echo "$COMPOSE_OUTPUT" | tail -20
    echo ""
    log_warn "Probamos levantar igual — docker compose up -d también valida."
fi

# =============================================================================
# 16. LIBERAR PUERTO 53 SI systemd-resolved LO OCUPA
# =============================================================================
log_step "PASO 16: Verificando systemd-resolved (conflicto DNS con Samba AD DC)"

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    log_warn "systemd-resolved está activo y PUEDE bloquear el puerto 53 (DNS)."
    log_warn "Samba AD DC necesita puerto 53 para funcionar como Domain Controller."

    if [[ -t 0 ]]; then
        echo ""
        log_ask "¿Deshabilitar systemd-resolved? [S/n] "
        read -r RESP || true
    else
        log_info "Ejecución no interactiva — deshabilitando systemd-resolved automáticamente"
        RESP="s"
    fi

    if [[ ! "$RESP" =~ ^[Nn]$ ]]; then
        log_info "Deshabilitando systemd-resolved..."
        systemctl disable --now systemd-resolved 2>/dev/null || true
        rm -f /etc/resolv.conf
        cat > /etc/resolv.conf <<'DNSRESOLV'
# Resolv.conf estático (systemd-resolved deshabilitado para Samba AD DC)
nameserver 1.1.1.1
nameserver 8.8.8.8
DNSRESOLV
        chattr +i /etc/resolv.conf 2>/dev/null || true
        log_ok "systemd-resolved deshabilitado. /etc/resolv.conf configurado manualmente."
    else
        log_warn "systemd-resolved se mantiene activo. Si Samba AD DC no levanta,"
        log_warn "       ejecutá: sudo systemctl disable --now systemd-resolved"
    fi
else
    log_ok "systemd-resolved no está activo — puerto 53 libre para Samba AD DC"
fi

# =============================================================================
# 17. VERIFICAR PUERTOS ANTES DE LEVANTAR
# =============================================================================
log_step "PASO 17: Verificando puertos en uso"

log_info "Buscando servicios que puedan entrar en conflicto..."
CONFLICT=0

CRITICAL_PORTS="53 88 135 389 445 464 636 8080 8081"
for PORT in $CRITICAL_PORTS; do
    if ss -tuln | grep -q ":${PORT} "; then
        log_warn "Puerto ${PORT} ya está en uso:"
        ss -tulnp | grep ":${PORT} " | head -1
        ((CONFLICT++))
    fi
done

if [[ $CONFLICT -gt 0 ]]; then
    log_warn "Hay $CONFLICT puerto(s) en uso que pueden causar conflictos."
    log_warn "Si son servicios del host que no necesitás, detenelos antes de continuar."

    if [[ -t 0 ]]; then
        echo ""
        log_ask "¿Continuar de todas formas? [s/N] "
        read -r RESP || true
        if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
            log_info "Saliendo. Liberá los puertos y volvé a ejecutar."
            exit 0
        fi
    else
        log_info "Ejecución no interactiva — continuando con puertos en conflicto"
    fi
else
    log_ok "Todos los puertos críticos están libres"
fi

# =============================================================================
# 18. LEVANTAR EL STACK
# =============================================================================
log_step "PASO 18: Levantando el stack Docker"

cd "$PROJECT_DIR"

log_info "Iniciando todos los servicios (docker compose up -d)..."
if docker compose up -d; then
    log_ok "Stack levantado — esperando a que los servicios estén healthy..."
else
    log_error "Fallo al levantar el stack. Revisá: docker compose logs"
    exit 1
fi

# =============================================================================
# 19. ESPERAR HEALTH CHECKS
# =============================================================================
log_step "PASO 19: Verificando salud de los servicios"

MAX_WAIT=180
WAITED=0
INTERVAL=10

log_info "Esperando hasta ${MAX_WAIT}s a que los servicios estén saludables..."

while [[ $WAITED -lt $MAX_WAIT ]]; do
    TOTAL=$(docker compose ps -q 2>/dev/null | wc -l)
    HEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"Health":"healthy"' || true)
    UNHEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"Health":"unhealthy"' || true)
    WITH_HC=$(docker compose ps --format json 2>/dev/null | grep -cE '"Health":"(healthy|starting|unhealthy)"' || true)

    echo -ne "  [${WAITED}s] Con healthcheck: ${HEALTHY:-0}/${WITH_HC:-0} healthy  |  Total contenedores: ${TOTAL:-0}\r"

    if [[ ${UNHEALTHY:-0} -gt 0 ]]; then
        echo ""
        log_warn "Hay ${UNHEALTHY} servicio(s) unhealthy:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | grep -i "unhealthy" || true
    fi

    if [[ ${WITH_HC:-0} -gt 0 ]] && [[ ${HEALTHY:-0} -eq ${WITH_HC:-0} ]]; then
        echo ""
        log_ok "¡Todos los servicios con healthcheck están saludables! (${HEALTHY}/${WITH_HC})"
        break
    fi

    if [[ ${WITH_HC:-0} -eq 0 ]] && [[ $WAITED -ge 30 ]]; then
        echo ""
        log_ok "Servicios levantados (sin healthchecks definidos — se esperó 30s)"
        break
    fi

    sleep $INTERVAL
    WAITED=$((WAITED + INTERVAL))
done

echo ""

# =============================================================================
# 20. MOSTRAR ESTADO FINAL
# =============================================================================
log_step "ESTADO FINAL DEL STACK"

echo ""
docker compose ps 2>/dev/null || true
echo ""

# ─── Resumen de acceso ───
log_step "RESUMEN DE ACCESO"

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi
[[ -z "$SERVER_IP" ]] && SERVER_IP="IP_DEL_SERVIDOR"

echo ""
echo -e "${GREEN}${BOLD}  Stack funcionando. URLs de acceso:${NC}"
echo ""
echo -e "  ${CYAN}Aplicación (Sistema Ventas):${NC}"
echo -e "    http://${SERVER_IP}:8080"
if is_enabled "$ENABLE_TLS"; then
    echo -e "    https://${SERVER_IP}:${TLS_APP_PORT}  (autofirmado si no cargaste uno propio)"
fi
echo ""
echo -e "  ${CYAN}Grafana (Monitoreo):${NC}"
echo -e "    http://${SERVER_IP}:8081"
if is_enabled "$ENABLE_TLS"; then
    echo -e "    https://${SERVER_IP}:${TLS_GRAFANA_PORT}"
fi
echo -e "    Usuario: admin"
echo -e "    Password: admin123  (cambiala en .env)"
echo ""
echo -e "  ${CYAN}Samba AD DC:${NC}"
echo -e "    Dominio:   ${SAMBA_DOMAIN:-proyecto.local}"
echo -e "    DC:        ${SAMBA_NETBIOS_NAME:-DC01}"
echo -e "    Admin:     Administrator"
echo -e "    Password:  ${SAMBA_ADMIN_PASSWORD:-Admin123!}"
echo ""
if is_enabled "$ENABLE_FAIL2BAN"; then
    echo -e "  ${CYAN}Fail2Ban:${NC} activo para SSH"
fi
if is_enabled "$ENABLE_ANTIMALWARE"; then
    echo -e "  ${CYAN}ClamAV:${NC} actualización + escaneo diario configurados"
fi
if is_enabled "$ENABLE_DHCP"; then
    echo -e "  ${CYAN}DHCP:${NC} activo en ${DHCP_INTERFACE} para red ${DHCP_SUBNET}/${DHCP_NETMASK}"
fi

# ─── Comandos útiles ───
log_step "COMANDOS ÚTILES"
echo ""
echo "  Ver logs de todos los servicios:"
echo -e "    ${BOLD}docker compose logs -f${NC}"
echo ""
echo "  Ver logs de un servicio específico:"
echo -e "    ${BOLD}docker compose logs -f app1${NC}"
echo ""
echo "  Reiniciar un servicio:"
echo -e "    ${BOLD}docker compose restart nginx${NC}"
echo ""
echo "  Bajar todo el stack:"
echo -e "    ${BOLD}docker compose down${NC}"
echo ""
echo "  Bajar TODO (incluyendo volúmenes — ¡pierde datos!):"
echo -e "    ${BOLD}docker compose down -v${NC}"
echo ""
echo "  Backup manual de base de datos:"
echo -e "    ${BOLD}docker compose exec backup-db-service sh -c 'pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/manual.sql.gz'${NC}"
echo ""
echo "  Ver backups realizados:"
echo -e "    ${BOLD}ls -la ${BACKUPS_DIR}/db/${NC}"
echo ""
echo "  Entrar al contenedor de Samba AD DC:"
echo -e "    ${BOLD}docker compose exec samba-ad-dc bash${NC}"
echo ""
echo "  Validar configuración de compose:"
echo -e "    ${BOLD}docker compose config${NC}"
echo ""

# ─── Próximos pasos ───
log_step "PRÓXIMOS PASOS RECOMENDADOS"
echo ""
echo "  1. Cambiá las contraseñas por defecto en .env:"
echo -e "     ${BOLD}nano ${ENV_FILE}${NC}"
echo "     Luego: ${BOLD}docker compose up -d${NC}"
echo ""
echo "  2. Verificá que la app responda:"
echo -e "     ${BOLD}curl -s http://localhost:8080 | head -20${NC}"
echo ""
echo "  3. Configurá dashboards en Grafana:"
echo -e "     Entrá a http://${SERVER_IP}:8081"
echo ""
echo "  4. Creá usuarios en el dominio Samba AD:"
echo -e "     ${BOLD}docker compose exec samba-ad-dc samba-tool user create usuario1 Password123!${NC}"
echo ""
echo "  5. Configurá rclone para backup en la nube (opcional):"
echo -e "     ${BOLD}docker run --rm -v ${RCLONE_CONFIG_DIR}:/config/rclone rclone/rclone config${NC}"
echo ""

log_step "INSTALACIÓN COMPLETADA"
echo ""
echo -e "  ${GREEN}${BOLD}✓${NC} El stack de Sistema de Ventas está corriendo en Ubuntu Server."
echo ""
echo "  Si algo falla, ejecutá ${BOLD}docker compose logs${NC} para diagnosticar."
echo "  El script es idempotente: podés re-ejecutarlo si necesitás reparar algo."
echo ""

exit 0
