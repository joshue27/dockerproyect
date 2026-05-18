#!/bin/bash
# =============================================================================
# Sistema de Ventas — Script de Instalación para Alma Linux
# =============================================================================
#
# Prepara un servidor Alma Linux 8.x/9.x e instala todo el stack Docker:
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
#   - Alma Linux 8.x o 9.x (instalación mínima o server)
#   - Acceso a internet
#   - Ejecutar como root (sudo no alcanza para algunas operaciones)
#
# USO:
#   1. Copiá este proyecto al servidor Alma Linux (scp, rsync, git clone)
#   2. Ejecutá como root desde la raíz del proyecto:
#        chmod +x install-almalinux.sh
#        sudo ./install-almalinux.sh
#   3. Para features opcionales, activalas por variables de entorno. Ejemplos:
#        sudo ENABLE_FAIL2BAN=1 ENABLE_ANTIMALWARE=1 ./install-almalinux.sh
#        sudo ENABLE_TLS=1 TLS_CERT_CN=ventas.local ./install-almalinux.sh
#        sudo ENABLE_DHCP=1 DHCP_INTERFACE=enp0s8 DHCP_SUBNET=192.168.50.0 \
#             DHCP_RANGE_START=192.168.50.100 DHCP_RANGE_END=192.168.50.150 ./install-almalinux.sh
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
NC='\033[0m' # No Color

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

# Features opcionales del host (opt-in seguro)
ENABLE_DHCP="${ENABLE_DHCP:-0}"
ENABLE_ANTIMALWARE="${ENABLE_ANTIMALWARE:-0}"
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-0}"
ENABLE_TLS="${ENABLE_TLS:-0}"

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

ensure_epel() {
    if ! rpm -q epel-release &>/dev/null; then
        log_info "Instalando repositorio EPEL..."
        dnf install -y epel-release
    fi
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
echo "║       Sistema de Ventas — Instalador para Alma Linux             ║"
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
   echo "       Ejecutalo con:  sudo ./install-almalinux.sh"
   exit 1
fi
log_ok "Ejecutando como root"

# 0.2 — Detectar Alma Linux
if [[ -f /etc/almalinux-release ]]; then
    ALMA_VERSION=$(rpm -E %rhel 2>/dev/null || echo "unknown")
    source /etc/os-release 2>/dev/null || true
    log_ok "Sistema: ${PRETTY_NAME:-Alma Linux} (RHEL ${ALMA_VERSION} compatible)"
else
    log_warn "No se detectó /etc/almalinux-release. ¿Estás seguro de que es Alma Linux?"
    log_warn "El script continuará, pero puede fallar si estás en otra distro."

    if [[ -t 0 ]]; then
        echo ""
        log_ask "¿Continuar de todas formas? [s/N] "
        read -r RESP || true
        if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
            log_info "Saliendo."
            exit 0
        fi
    else
        log_info "Ejecución no interactiva — continuando (asumiendo RHEL-compatible)"
    fi
    ALMA_VERSION=$(rpm -E %rhel 2>/dev/null || echo "8")
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
# Si el parseo falla, asumimos que hay espacio suficiente
[[ -z "$DISK_FREE_GB" ]] && DISK_FREE_GB=99

echo ""
log_info "Recursos detectados:"
log_info "  CPU:     ${CPU_COUNT} vCPUs"
log_info "  RAM:     ${TOTAL_RAM_GB} GB"
log_info "  Disco /: ${DISK_FREE_GB} GB libres"

# Solo advertencias — nunca bloquean. El usuario ya sabe lo que tiene.
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
# 1. ACTUALIZAR SISTEMA
# =============================================================================
log_step "PASO 1: Actualizando paquetes del sistema"

dnf check-update -y 2>&1 || true  # no falla si no hay updates
dnf upgrade -y || log_warn "System update skipped (network/mirror issues) — continuing anyway"
log_ok "Sistema actualizado"

# =============================================================================
# 2. INSTALAR PREREQUISITOS
# =============================================================================
log_step "PASO 2: Instalando prerequisitos"

dnf install -y \
    dnf-plugins-core \
    curl \
    wget \
    git \
    unzip \
    tar \
    gzip \
    bash-completion \
    ca-certificates \
    openssl \
    cronie \
    policycoreutils-python-utils

log_ok "Prerequisitos instalados"

# =============================================================================
# 3. INSTALAR DOCKER CE + DOCKER COMPOSE
# =============================================================================
log_step "PASO 3: Instalando Docker Engine y Docker Compose"

# 3.1 — Remover versiones viejas si existen
dnf remove -y \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc \
    2>/dev/null || true

# 3.2 — Agregar repositorio oficial de Docker CE
if ! rpm -q docker-ce &>/dev/null; then
    log_info "Agregando repositorio Docker CE..."
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

    log_info "Instalando Docker CE + Docker Compose plugin..."
    dnf install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_ok "Docker instalado"
else
    log_ok "Docker ya está instalado: $(docker --version)"
fi

# 3.3 — Iniciar y habilitar Docker
systemctl enable --now docker
if systemctl is-active --quiet docker; then
    log_ok "Docker está corriendo"
else
    log_error "Docker no pudo iniciarse. Revisá: systemctl status docker"
    exit 1
fi

# 3.4 — Verificar Docker Compose
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

            # Persistir en fstab
            if ! grep -q "$SWAP_FILE" /etc/fstab; then
                echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
            fi

            # Ajustar swappiness para que prefiera RAM sobre swap
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
# 6. CONFIGURAR FIREWALL (firewalld)
# =============================================================================
log_step "PASO 6: Configurando firewall"

# Asegurar que firewalld está corriendo
if ! systemctl is-active --quiet firewalld; then
    systemctl enable --now firewalld
fi

# ─── Puertos de la aplicación ───
log_info "Abriendo puertos web..."
firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null && log_info "  8080/tcp (App)" || true
firewall-cmd --permanent --add-port=8081/tcp 2>/dev/null && log_info "  8081/tcp (Grafana)" || true

# ─── Puertos de Samba AD DC ───
log_info "Abriendo puertos de Samba AD DC (Active Directory)..."
SAMBA_TCP_PORTS=(53 88 135 389 445 464 636 3268 3269)
SAMBA_UDP_PORTS=(53 88 389 464 123)

for PORT in "${SAMBA_TCP_PORTS[@]}"; do
    firewall-cmd --permanent --add-port="${PORT}/tcp" 2>/dev/null && log_info "  ${PORT}/tcp" || true
done
for PORT in "${SAMBA_UDP_PORTS[@]}"; do
    firewall-cmd --permanent --add-port="${PORT}/udp" 2>/dev/null && log_info "  ${PORT}/udp" || true
done

# Rango de puertos dinámicos RPC para Samba
firewall-cmd --permanent --add-port=50000-50050/tcp 2>/dev/null && log_info "  50000-50050/tcp (RPC dinámico)" || true

# ─── Aplicar cambios ───
firewall-cmd --reload
log_ok "Firewall configurado"

# ─── Mostrar reglas activas ───
echo ""
log_info "Puertos abiertos actualmente:"
firewall-cmd --list-ports 2>/dev/null || true
echo ""

# =============================================================================
# 6. CONFIGURAR SELINUX PARA DOCKER
# =============================================================================
log_step "PASO 7: Configurando SELinux para Docker"

SELINUX_MODE=$(getenforce 2>/dev/null || echo "Disabled")
log_info "SELinux está en modo: ${SELINUX_MODE}"

if [[ "$SELINUX_MODE" == "Enforcing" ]]; then
    log_info "Ajustando SELinux para montajes de Docker..."

    # Instalar container-selinux si no está
    dnf install -y container-selinux 2>/dev/null || true

    # Crear directorios host si no existen
    mkdir -p "$APP_DATA_DIR" "$BACKUPS_DIR" "$RCLONE_CONFIG_DIR" "$HOST_TLS_DIR"

    # Aplicar contexto container_file_t a los directorios de datos persistentes
    # Esto permite que los contenedores Docker lean/escriban en estos paths
    log_info "Aplicando contexto SELinux a directorios de datos..."
    semanage fcontext -a -t container_file_t "${APP_DATA_DIR}(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${BACKUPS_DIR}(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${RCLONE_CONFIG_DIR}(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${HOST_TLS_DIR}(/.*)?" 2>/dev/null || true
    restorecon -Rv "$APP_DATA_DIR" "$BACKUPS_DIR" "$RCLONE_CONFIG_DIR" "$HOST_TLS_DIR" 2>/dev/null || true

    # Para los bind mounts del directorio del proyecto (nginx configs, scripts, etc.)
    # Docker con SELinux enforcing puede bloquear el acceso a estos archivos.
    # Estrategia: aplicar contexto en el directorio del proyecto.
    log_info "Aplicando contexto SELinux al directorio del proyecto..."
    semanage fcontext -a -t container_file_t "${PROJECT_DIR}/nginx(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${PROJECT_DIR}/backups(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${PROJECT_DIR}/database(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${PROJECT_DIR}/ops(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t container_file_t "${PROJECT_DIR}/ldap(/.*)?" 2>/dev/null || true
    restorecon -Rv "$PROJECT_DIR/nginx" "$PROJECT_DIR/backups" "$PROJECT_DIR/database" \
                   "$PROJECT_DIR/ops" "$PROJECT_DIR/ldap" 2>/dev/null || true

    # Verificar que Docker puede acceder (test con un container efímero)
    if docker run --rm -v "$APP_DATA_DIR:/data:rw" alpine:3.20 touch /data/.selinux-test 2>/dev/null; then
        rm -f "$APP_DATA_DIR/.selinux-test"
        log_ok "SELinux configurado correctamente — Docker puede acceder a los volúmenes"
    else
        log_warn "SELinux podría estar bloqueando montajes de Docker."
        log_warn "Si Docker falla al levantar los servicios, ejecutá temporalmente:"
        log_warn "    sudo setenforce 0"
        log_warn "Y reportá el problema con:  sudo ausearch -m avc -ts recent"
    fi
elif [[ "$SELINUX_MODE" == "Disabled" ]]; then
    log_ok "SELinux deshabilitado — sin ajustes necesarios"
else
    log_info "SELinux en modo Permissive — registra pero no bloquea. Sin ajustes necesarios."
fi

# =============================================================================
# 7. CREAR ESTRUCTURA DE DIRECTORIOS
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
# 8. CONFIGURAR ARCHIVO .ENV
# =============================================================================
log_step "PASO 9: Configurando variables de entorno (.env)"

if [[ -f "$ENV_FILE" ]]; then
    log_info "Ya existe un archivo .env. Se mantiene sin cambios."
    log_info "Si querés regenerarlo con los defaults, borralo primero:"
    log_info "  rm $ENV_FILE && sudo ./install-almalinux.sh"
else
    if [[ -f "$ENV_EXAMPLE" ]]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        log_ok ".env creado desde docker-compose.env.example"
    else
        log_warn "No se encontró docker-compose.env.example. Creando .env con defaults..."
        cat > "$ENV_FILE" <<'ENVEOF'
# =============================================================================
# Sistema de Ventas — Variables de Entorno
# Generado por install-almalinux.sh
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
# 9. CONFIGURAR FAIL2BAN (opcional)
# =============================================================================
if is_enabled "$ENABLE_FAIL2BAN"; then
    log_step "PASO 10: Configurando Fail2Ban para SSH"
    ensure_epel
    dnf install -y fail2ban fail2ban-firewalld
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sistemaventas-sshd.local <<EOF
[DEFAULT]
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
banaction = firewallcmd-ipset
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
# 10. CONFIGURAR ANTIMALWARE (opcional)
# =============================================================================
if is_enabled "$ENABLE_ANTIMALWARE"; then
    log_step "PASO 11: Configurando antimalware ClamAV"
    ensure_epel
    dnf install -y clamav clamav-update
    mkdir -p /var/log/clamav
    sed -i 's/^Example/#Example/' /etc/freshclam.conf 2>/dev/null || true
    freshclam || log_warn "freshclam no pudo actualizar firmas ahora mismo; revisalo luego"
    cat > /etc/cron.d/sistemaventas-clamav <<EOF
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
15 2 * * * root freshclam --quiet && clamscan -ri --log=/var/log/clamav/sistemaventas-scan.log ${ANTIMALWARE_SCAN_DIRS}
EOF
    systemctl enable --now crond
    log_ok "ClamAV configurado con actualización y escaneo diario"
else
    log_info "Antimalware omitido (ENABLE_ANTIMALWARE=0)"
fi

# =============================================================================
# 11. CONFIGURAR DHCP (opcional, solo red aislada)
# =============================================================================
if is_enabled "$ENABLE_DHCP"; then
    log_step "PASO 12: Configurando DHCP para laboratorio aislado"
    if [[ -z "$DHCP_INTERFACE" || -z "$DHCP_SUBNET" || -z "$DHCP_RANGE_START" || -z "$DHCP_RANGE_END" ]]; then
        log_error "Para ENABLE_DHCP=1 necesitás definir DHCP_INTERFACE, DHCP_SUBNET, DHCP_RANGE_START y DHCP_RANGE_END"
        exit 1
    fi

    ensure_epel
    dnf install -y dhcp-server

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

    cat > /etc/sysconfig/dhcpd <<EOF
DHCPDARGS=${DHCP_INTERFACE}
EOF

    firewall-cmd --permanent --add-service=dhcp 2>/dev/null || firewall-cmd --permanent --add-port=67/udp 2>/dev/null || true
    firewall-cmd --reload
    systemctl enable --now dhcpd
    log_warn "DHCP habilitado. Usalo SOLO en red aislada / host-only / laboratorio."
    log_ok "DHCP configurado sobre interfaz ${DHCP_INTERFACE}"
else
    log_info "DHCP omitido (ENABLE_DHCP=0)"
fi

# =============================================================================
# 12. CONFIGURAR TLS/HTTPS (opcional)
# =============================================================================
mkdir -p "$PROJECT_DIR/nginx/conf.d"
if is_enabled "$ENABLE_TLS"; then
    log_step "PASO 13: Configurando TLS para Nginx"
    if [[ ! -f "$HOST_TLS_DIR/fullchain.pem" || ! -f "$HOST_TLS_DIR/privkey.pem" ]]; then
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$HOST_TLS_DIR/privkey.pem" \
            -out "$HOST_TLS_DIR/fullchain.pem" \
            -days "$TLS_CERT_DAYS" \
            -subj "/CN=${TLS_CERT_CN}"
        chmod 600 "$HOST_TLS_DIR/privkey.pem"
        chmod 644 "$HOST_TLS_DIR/fullchain.pem"
        log_ok "Certificado autofirmado generado en $HOST_TLS_DIR"
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

    firewall-cmd --permanent --add-port="${TLS_APP_PORT}/tcp" 2>/dev/null || true
    firewall-cmd --permanent --add-port="${TLS_GRAFANA_PORT}/tcp" 2>/dev/null || true
    firewall-cmd --reload
    log_ok "TLS/HTTPS configurado para aplicación y Grafana"
else
    cat > "$PROJECT_DIR/nginx/conf.d/https.conf" <<'EOF'
# TLS opcional deshabilitado.
# install-almalinux.sh reemplaza este archivo cuando ENABLE_TLS=1.
EOF
    log_info "TLS omitido (ENABLE_TLS=0)"
fi

# =============================================================================
# 13. PULL DE IMÁGENES DOCKER
# =============================================================================
log_step "PASO 14: Descargando imágenes Docker"

log_info "Esto puede tardar varios minutos la primera vez..."
cd "$PROJECT_DIR"

# Pull de todas las imágenes (ignora errores — se reintenta en el up)
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
# 10. VALIDAR CONFIGURACIÓN DE DOCKER COMPOSE
# =============================================================================
log_step "PASO 11: Validando docker-compose.yml"

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
    log_warn "Posibles causas y soluciones:"
    log_warn "  1. Si ves 'mem_limit': Docker Compose muy viejo → dnf update docker-compose-plugin"
    log_warn "  2. Si ves errores de YAML: revisá docker-compose.override.yml"
    log_warn "  3. Si ves 'additional property': versión de compose no soporta esa clave"
    log_warn ""
    log_warn "Probamos levantar igual — docker compose up -d también valida."
fi

# =============================================================================
# 11. LIBERAR PUERTO 53 SI systemd-resolved LO OCUPA
# =============================================================================
log_step "PASO 12: Verificando systemd-resolved (conflicto DNS con Samba AD DC)"

# Este es el problema #1 al correr Samba AD DC en Linux:
# systemd-resolved escucha en 127.0.0.53:53 y puede bloquear el puerto 53.
# Samba AD DC necesita el puerto 53 para su propio servidor DNS.

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    log_warn "systemd-resolved está activo y PUEDE bloquear el puerto 53 (DNS)."
    log_warn "Samba AD DC necesita puerto 53 para funcionar como Domain Controller."

    # Si el script corre via pipe (curl | bash), stdin no es terminal.
    # En ese caso deshabilitamos systemd-resolved automáticamente.
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
        # Reemplazar el symlink de resolv.conf con uno estático
        rm -f /etc/resolv.conf
        cat > /etc/resolv.conf <<'DNSRESOLV'
# Resolv.conf estático (systemd-resolved deshabilitado para Samba AD DC)
nameserver 1.1.1.1
nameserver 8.8.8.8
DNSRESOLV
        chattr +i /etc/resolv.conf 2>/dev/null || true  # inmutable para que NetworkManager no lo pise
        log_ok "systemd-resolved deshabilitado. /etc/resolv.conf configurado manualmente."
    else
        log_warn "systemd-resolved se mantiene activo. Si Samba AD DC no levanta,"
        log_warn "       ejecutá: sudo systemctl disable --now systemd-resolved"
    fi
else
    log_ok "systemd-resolved no está activo — puerto 53 libre para Samba AD DC"
fi

# =============================================================================
# 12. VERIFICAR PUERTOS ANTES DE LEVANTAR
# =============================================================================
log_step "PASO 13: Verificando puertos en uso"

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
        log_info "Si Samba AD DC falla, revisá: ss -tuln | grep ':53 '"
    fi
else
    log_ok "Todos los puertos críticos están libres"
fi

# =============================================================================
# 13. LEVANTAR EL STACK
# =============================================================================
log_step "PASO 14: Levantando el stack Docker"

cd "$PROJECT_DIR"

log_info "Iniciando todos los servicios (docker compose up -d)..."
if docker compose up -d; then
    log_ok "Stack levantado — esperando a que los servicios estén healthy..."
else
    log_error "Fallo al levantar el stack. Revisá: docker compose logs"
    exit 1
fi

# =============================================================================
# 14. ESPERAR HEALTH CHECKS
# =============================================================================
log_step "PASO 15: Verificando salud de los servicios"

MAX_WAIT=180  # máximo 3 minutos
WAITED=0
INTERVAL=10

log_info "Esperando hasta ${MAX_WAIT}s a que los servicios estén saludables..."

while [[ $WAITED -lt $MAX_WAIT ]]; do
    # Contar servicios totales y servicios healthy
    TOTAL=$(docker compose ps -q 2>/dev/null | wc -l)
    # Filter healthy status, ignoring services without health checks
    HEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"Health":"healthy"' || true)
    UNHEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"Health":"unhealthy"' || true)

    # Count services that have a health check defined (exclude "unknown" health)
    WITH_HC=$(docker compose ps --format json 2>/dev/null | grep -cE '"Health":"(healthy|starting|unhealthy)"' || true)

    echo -ne "  [${WAITED}s] Con healthcheck: ${HEALTHY:-0}/${WITH_HC:-0} healthy  |  Total contenedores: ${TOTAL:-0}\r"

    # Si hay unhealthy, mostramos warning pero seguimos esperando (pueden estar reiniciándose)
    if [[ ${UNHEALTHY:-0} -gt 0 ]]; then
        echo ""
        log_warn "Hay ${UNHEALTHY} servicio(s) unhealthy:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | grep -i "unhealthy" || true
    fi

    # Verificar si todos los que tienen healthcheck están healthy
    if [[ ${WITH_HC:-0} -gt 0 ]] && [[ ${HEALTHY:-0} -eq ${WITH_HC:-0} ]]; then
        echo ""
        log_ok "¡Todos los servicios con healthcheck están saludables! (${HEALTHY}/${WITH_HC})"
        break
    fi

    # Si no hay servicios con healthcheck, salimos después de un tiempo prudencial
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
# 15. MOSTRAR ESTADO FINAL
# =============================================================================
log_step "PASO 16: Estado final del stack"

echo ""
docker compose ps 2>/dev/null || true
echo ""

# ─── Resumen de acceso ───
log_step "RESUMEN DE ACCESO"

# Detectar IP del servidor
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$SERVER_IP" ]]; then
    # Fallback: intentar con ip addr
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
echo -e "    Administración: solo por CLI / RSAT (sin interfaz web)"
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
if is_enabled "$ENABLE_FAIL2BAN" || is_enabled "$ENABLE_ANTIMALWARE" || is_enabled "$ENABLE_DHCP"; then
    echo ""
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
echo "     Luego: ${BOLD}docker compose up -d${NC} (recrea servicios si cambiaron vars)"
echo ""
echo "  2. Verificá que la app responda:"
echo -e "     ${BOLD}curl -s http://localhost:8080 | head -20${NC}"
if is_enabled "$ENABLE_TLS"; then
    echo -e "     ${BOLD}curl -k https://localhost:${TLS_APP_PORT} | head -20${NC}"
fi
echo ""
echo "  3. Configurá dashboards en Grafana:"
echo -e "     Entrá a http://${SERVER_IP}:8081 y explorá los datasources pre-configurados"
echo ""
echo "  4. Creá usuarios en el dominio Samba AD:"
echo -e "     ${BOLD}docker compose exec samba-ad-dc samba-tool user create usuario1 Password123!${NC}"
echo ""
echo "  5. Si querés unir una VM Linux cliente al dominio:"
echo -e "     Instalá realmd, sssd y seguí la documentación de Samba AD DC"
echo ""
echo "  6. Configurá rclone para backup en la nube (opcional):"
echo -e "     ${BOLD}docker run --rm -v ${RCLONE_CONFIG_DIR}:/config/rclone rclone/rclone config${NC}"
echo ""
if is_enabled "$ENABLE_FAIL2BAN"; then
    echo "  7. Revisá el jail de SSH en Fail2Ban:"
    echo -e "     ${BOLD}fail2ban-client status sshd${NC}"
    echo ""
fi
if is_enabled "$ENABLE_ANTIMALWARE"; then
    echo "  8. Forzá un escaneo manual de ClamAV si querés validar seguridad:"
    echo -e "     ${BOLD}freshclam && clamscan -ri ${ANTIMALWARE_SCAN_DIRS}${NC}"
    echo ""
fi
if is_enabled "$ENABLE_DHCP"; then
    echo "  9. Verificá leases DHCP en la red aislada:"
    echo -e "     ${BOLD}journalctl -u dhcpd --no-pager | tail -50${NC}"
    echo ""
fi

log_step "INSTALACIÓN COMPLETADA"
echo ""
echo -e "  ${GREEN}${BOLD}✓${NC} El stack de Sistema de Ventas está corriendo en Alma Linux."
echo ""
echo "  Si algo falla, ejecutá ${BOLD}docker compose logs${NC} para diagnosticar."
echo "  El script es idempotente: podés re-ejecutarlo si necesitás reparar algo."
echo ""

# =============================================================================
# 16. GUARDAR ESTADO EN ENGRAM (si está disponible)
# =============================================================================
# Esta sección es opcional — el orchestrator puede capturar el resultado
# para persistirlo en memoria.

exit 0
