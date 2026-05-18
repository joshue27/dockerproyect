#!/bin/bash
# =============================================================================
# Sistema de Ventas — Bootstrap para Ubuntu Server
# =============================================================================
#
# UN SOLO SCRIPT. Clona el repo y ejecuta la instalación completa.
#
# USO (en una VM Ubuntu Server recién instalada):
#
#   curl -fsSL https://raw.githubusercontent.com/joshue27/dockerproyect/main/bootstrap-ubuntu.sh | sudo bash
#
# O si ya bajaste el script:
#
#   chmod +x bootstrap-ubuntu.sh
#   sudo ./bootstrap-ubuntu.sh
#
# REQUISITOS:
#   - Ubuntu Server 22.04 o 24.04 LTS (instalación mínima)
#   - 4 vCPU / 8 GB RAM / 40 GB disco
#   - Acceso a internet
#   - Ejecutar como root
#
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="https://github.com/joshue27/dockerproyect.git"
INSTALL_DIR="/opt/dockerproyect"

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║   Sistema de Ventas — Bootstrap Ubuntu Server                   ║"
echo "║   Clona el repo + ejecuta instalación completa                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Root check ────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutá como root:  sudo ./bootstrap-ubuntu.sh"
    exit 1
fi

# ─── Instalar git (si no está) ─────────────────────────────────────────
if ! command -v git &>/dev/null; then
    echo "Instalando git..."
    apt-get update -y && apt-get install -y git
fi

# ─── Clonar o actualizar el repo ───────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Repositorio ya existe en $INSTALL_DIR — actualizando..."
    cd "$INSTALL_DIR"
    git pull origin main
else
    echo "Clonando repositorio en $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# ─── Ejecutar el instalador ────────────────────────────────────────────
echo ""
echo "Ejecutando instalador para Ubuntu Server..."
echo ""

chmod +x install-ubuntu.sh
exec ./install-ubuntu.sh
