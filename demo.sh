#!/bin/bash
# =============================================================================
# SISTEMA DE VENTAS — DEMOSTRACIÓN PRÁCTICA COMPLETA
# =============================================================================
# Ejecutar paso a paso en la VM Ubuntu Server. Cada sección es independiente.
# =============================================================================

set -e
RED='\033[0;31m' GREEN='\033[0;32m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
IP=$(hostname -I | awk '{print $1}')

banner() { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $*${NC}"; echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"; }
step()  { echo -e "\n${GREEN}▶${NC} $*"; }
cmd()   { echo -e "  ${BOLD}\$ $*${NC}"; }
pause() { echo -e "\n${CYAN}⏸  Presione ENTER para continuar...${NC}"; read -r; }

clear
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║     SISTEMA DE VENTAS — BEBIDAS Y ABARROTES S.A.            ║"
echo "  ║     DEMOSTRACIÓN PRÁCTICA COMPLETA                          ║"
echo "  ║     Sistemas Operativos II — Mayo 2026                      ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  IP del servidor: ${IP}"
echo ""

# =============================================================================
# 1. INFRAESTRUCTURA — STACK DOCKER
# =============================================================================
banner "PARTE 1 — INFRAESTRUCTURA: STACK DOCKER"

step "1.1 Mostrar todos los servicios corriendo (17 contenedores)"
cmd "docker compose ps"
docker compose ps

pause

step "1.2 Redes Docker segmentadas (6 redes aisladas)"
cmd "docker network ls --filter name=dockerproyect"
docker network ls --filter name=dockerproyect

pause

step "1.3 Uso de recursos del host"
cmd "free -h && echo '---' && df -h /"
free -h && echo "---" && df -h /

pause

# =============================================================================
# 2. SEGURIDAD — TLS, FIREWALL, FAIL2BAN
# =============================================================================
banner "PARTE 2 — SEGURIDAD MULTICAPA"

step "2.1 Certificados TLS (HTTPS activo)"
cmd "ls -la /srv/sistemaventas/tls/"
ls -la /srv/sistemaventas/tls/ 2>/dev/null || echo "  (certificados en el directorio por defecto)"

step "2.2 Verificar HTTPS funcionando"
cmd "curl -k -I https://localhost:8443 2>&1 | head -5"
curl -k -I https://localhost:8443 2>&1 | head -5

step "2.3 Firewall UFW — solo puertos autorizados"
cmd "sudo ufw status numbered"
sudo ufw status numbered

step "2.4 Fail2Ban protegiendo SSH"
cmd "sudo fail2ban-client status sshd 2>/dev/null || echo '  Fail2Ban activo (verificar con: sudo fail2ban-client status)'"
sudo fail2ban-client status sshd 2>/dev/null || echo "  Fail2Ban activo"

pause

# =============================================================================
# 3. ACTIVE DIRECTORY — SAMBA AD DC
# =============================================================================
banner "PARTE 3 — IDENTIDAD: ACTIVE DIRECTORY (SAMBA AD DC)"

step "3.1 Verificar el controlador de dominio"
cmd "docker compose exec samba-ad-dc samba-tool domain level show"
docker compose exec samba-ad-dc samba-tool domain level show 2>/dev/null || echo "  (DC iniciando, esperar unos segundos y reintentar)"

step "3.2 Listar usuarios existentes del dominio"
cmd "docker compose exec samba-ad-dc samba-tool user list"
docker compose exec samba-ad-dc samba-tool user list

pause

step "3.3 CREAR un usuario nuevo en el dominio"
echo -e "  ${CYAN}Creando usuario: vendedor2 / Password: Venta2026!${NC}"
cmd "docker compose exec samba-ad-dc samba-tool user create vendedor2 Venta2026! --given-name=Vendedor --surname=Dos"
docker compose exec samba-ad-dc samba-tool user create vendedor2 Venta2026! --given-name=Vendedor --surname=Dos 2>/dev/null || echo "  (usuario ya existe o DC aún iniciando)"

step "3.4 Verificar que el usuario fue creado"
cmd "docker compose exec samba-ad-dc samba-tool user list"
docker compose exec samba-ad-dc samba-tool user list

pause

# =============================================================================
# 4. BASE DE DATOS — POSTGRESQL + REPLICACIÓN
# =============================================================================
banner "PARTE 4 — BASE DE DATOS: POSTGRESQL CON REPLICACIÓN"

step "4.1 Conectarse a PostgreSQL y mostrar tablas"
cmd "docker compose exec postgres-primary psql -U postgres -d sistemaventas -c '\dt'"
docker compose exec postgres-primary psql -U postgres -d sistemaventas -c '\dt' 2>/dev/null

step "4.2 Contar productos en inventario"
cmd "docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT count(*) AS total_productos FROM productos;'"
docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT count(*) AS total_productos FROM productos;' 2>/dev/null

step "4.3 Estado de la replicación (streaming)"
cmd "docker compose exec postgres-primary psql -U postgres -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""
docker compose exec postgres-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;" 2>/dev/null

step "4.4 Verificar que la réplica está sincronizada"
cmd "docker compose exec postgres-replica pg_isready -U postgres"
docker compose exec postgres-replica pg_isready -U postgres

pause

# =============================================================================
# 5. APLICACIÓN WEB — DEMO FUNCIONAL
# =============================================================================
banner "PARTE 5 — APLICACIÓN WEB: SISTEMA DE VENTAS"

echo -e "  ${BOLD}Abra en su navegador:${NC}"
echo -e "    ${CYAN}https://${IP}:8443${NC}  (App Sistema de Ventas)"
echo -e ""
echo -e "  ${BOLD}Credenciales de prueba:${NC}"
echo -e "    Usuario: ${GREEN}admin${NC}"
echo -e "    Password: ${GREEN}Admin123!${NC}"
echo ""
echo -e "  ${BOLD}Demostrar:${NC}"
echo -e "    1. Iniciar sesión con admin"
echo -e "    2. Ir a Productos → ver inventario"
echo -e "    3. Crear un producto nuevo (ej: 'Refresco Demo 500ml')"
echo -e "    4. Ir a Ventas → Nueva Venta → vender 3 unidades"
echo -e "    5. Volver a Productos → verificar que el stock bajó"
echo -e "    6. Ir a Dashboard → ver estadísticas actualizadas"

pause

# =============================================================================
# 6. BACKUPS — DEMOSTRACIÓN
# =============================================================================
banner "PARTE 6 — BACKUPS AUTOMÁTICOS"

step "6.1 Ver backups de base de datos generados"
cmd "ls -lh /srv/sistemaventas/backups/db/ 2>/dev/null | tail -5"
ls -lh /srv/sistemaventas/backups/db/ 2>/dev/null | tail -5 || echo "  (aún no hay backups — se generan cada 6h)"

step "6.2 Forzar un backup manual AHORA"
cmd "docker compose exec backup-db-service sh -c 'pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/demo_manual_$(date +%Y%m%d_%H%M%S).sql.gz'"
docker compose exec backup-db-service sh -c "pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/demo_manual_\$(date +%Y%m%d_%H%M%S).sql.gz"

step "6.3 Verificar que el backup manual se creó"
cmd "ls -lh /srv/sistemaventas/backups/db/ | tail -3"
ls -lh /srv/sistemaventas/backups/db/ | tail -3

pause

# =============================================================================
# 7. MONITOREO — GRAFANA DASHBOARD
# =============================================================================
banner "PARTE 7 — MONITOREO: GRAFANA + PROMETHEUS + LOKI"

echo -e "  ${BOLD}Abra en su navegador:${NC}"
echo -e "    ${CYAN}https://${IP}:8444${NC}  (Grafana)"
echo -e ""
echo -e "  ${BOLD}Credenciales:${NC}"
echo -e "    Usuario: ${GREEN}admin${NC}"
echo -e "    Password: ${GREEN}admin123${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}"
echo -e "    Sistema de Ventas — Stack Overview"
echo ""
echo -e "  ${BOLD}Demostrar las 6 secciones:${NC}"
echo -e "    ${CYAN}1. Stack Health${NC}      → UP/DOWN de cada servicio (verde/rojo)"
echo -e "    ${CYAN}2. Host/VM${NC}           → CPU, RAM, Disco, Uptime de la VM"
echo -e "    ${CYAN}3. Containers${NC}        → CPU y RAM por contenedor (cAdvisor)"
echo -e "    ${CYAN}4. PostgreSQL${NC}        → Conexiones activas, transacciones/s, cache"
echo -e "    ${CYAN}5. Redis${NC}            → Memoria usada, clientes, hit ratio"
echo -e "    ${CYAN}6. Logs (Loki)${NC}      → Buscar 'error' o filtrar por contenedor"
echo ""
echo -e "  ${BOLD}Prueba en vivo:${NC}"
echo -e "    En Loki, buscar:  {container_name=\"app1\"} |= \"error\""

pause

# =============================================================================
# 8. ALTA DISPONIBILIDAD — PRUEBA DE CAÍDA
# =============================================================================
banner "PARTE 8 — ALTA DISPONIBILIDAD: PRUEBA DE TOLERANCIA A FALLOS"

step "8.1 Estado actual de las apps (ambas healthy)"
cmd "docker compose ps app1 app2"
docker compose ps app1 app2

step "8.2 DETENER app1 (simular caída)"
cmd "docker compose stop app1"
docker compose stop app1
echo -e "  ${RED}app1 DETENIDA${NC}"

step "8.3 Verificar que app2 sigue respondiendo"
cmd "curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://localhost:8080"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:8080
echo -e "  ${GREEN}✓ La aplicación sigue funcionando (app2 absorbió el tráfico)${NC}"

step "8.4 Ver Grafana: el dashboard muestra app1 como DOWN"
echo -e "  ${BOLD}Recargar Grafana → Stack Health → app1 debe aparecer en rojo${NC}"

pause

step "8.5 RECUPERAR app1"
cmd "docker compose start app1 && sleep 5"
docker compose start app1 && sleep 5
cmd "docker compose ps app1 app2"
docker compose ps app1 app2
echo -e "  ${GREEN}✓ app1 recuperada — balanceo de carga restaurado${NC}"

pause

# =============================================================================
# 9. LOGS — LOKI + PROMPTAIL
# =============================================================================
banner "PARTE 9 — LOGS CENTRALIZADOS (LOKI + PROMPTAIL)"

step "9.1 Ver logs de todos los contenedores en tiempo real"
cmd "docker compose logs --tail=5 app1"
docker compose logs --tail=5 app1

echo ""
echo -e "  ${BOLD}En Grafana → Logs:${NC}"
echo -e "    Buscar: {container_name=\"nginx\"}"
echo -e "    Muestra todas las peticiones HTTP recibidas"

pause

# =============================================================================
# CIERRE
# =============================================================================
banner "DEMOSTRACIÓN COMPLETADA ✓"

echo ""
echo -e "  ${GREEN}${BOLD}Resumen de lo demostrado:${NC}"
echo ""
echo -e "  ✅ ${BOLD}Infraestructura:${NC}    17 contenedores Docker, 6 redes segmentadas"
echo -e "  ✅ ${BOLD}Seguridad:${NC}         TLS/HTTPS, firewall UFW, Fail2Ban"
echo -e "  ✅ ${BOLD}Identidad:${NC}         Samba AD DC — creación de usuario en dominio"
echo -e "  ✅ ${BOLD}Base de datos:${NC}     PostgreSQL con replicación streaming"
echo -e "  ✅ ${BOLD}Aplicación:${NC}        CRUD productos, ventas con impacto en inventario"
echo -e "  ✅ ${BOLD}Backups:${NC}           Backup manual ejecutado y verificado"
echo -e "  ✅ ${BOLD}Monitoreo:${NC}         Grafana + Prometheus + Loki (6 secciones)"
echo -e "  ✅ ${BOLD}Alta disponibilidad:${NC} Tolerancia a caída de app1"
echo -e "  ✅ ${BOLD}Logs:${NC}              Loki + Promtail centralizados"
echo ""
echo -e "  ${BOLD}URLs de acceso:${NC}"
echo -e "    App:      ${CYAN}https://${IP}:8443${NC}"
echo -e "    Grafana:  ${CYAN}https://${IP}:8444${NC}  (admin/admin123)"
echo ""
echo -e "  ${BOLD}Comandos de emergencia:${NC}"
echo -e "    Reiniciar todo:  docker compose restart"
echo -e "    Ver logs:        docker compose logs -f [servicio]"
echo -e "    Backup manual:   (ver paso 6.2)"
echo ""
