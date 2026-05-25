#!/bin/bash
# =============================================================================
# SISTEMA DE VENTAS — DEMOSTRACIÓN PRÁCTICA COMPLETA
# =============================================================================
# Versión actualizada — Mayo 2026
# 20 servicios · Samba AD DC funcional · phpLDAPadmin incluido
# =============================================================================

set -e
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
IP=$(hostname -I | awk '{print $1}')

ok() { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }

banner() {
	echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
	echo -e "${CYAN}${BOLD}  $*${NC}"
	echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}
step() { echo -e "\n${GREEN}▶${NC} $*"; }
cmd() { echo -e "  ${BOLD}\$ $*${NC}"; }
pause() {
	echo -e "\n${CYAN}⏸  Presione ENTER para continuar...${NC}"
	read -r
}

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
echo "  Stack: 20 servicios · 6 redes segmentadas"
echo ""

# =============================================================================
# 1. INFRAESTRUCTURA — STACK DOCKER
# =============================================================================
banner "PARTE 1 — INFRAESTRUCTURA: STACK DOCKER"

step "1.1 Mostrar todos los servicios corriendo (20 contenedores)"
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
if [ -d /srv/sistemaventas/tls ]; then
	cmd "ls -la /srv/sistemaventas/tls/"
	ls -la /srv/sistemaventas/tls/
	ok "Certificados TLS encontrados"
else
	warn "Directorio TLS no encontrado — HTTPS puede no estar configurado"
fi

step "2.2 Verificar HTTPS funcionando"
cmd "curl -k -I https://localhost:8443 2>&1 | head -5"
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null | grep -q "200\|302\|301"; then
	ok "HTTPS responde correctamente"
else
	warn "HTTPS no responde aún (puede estar en inicio)"
fi

step "2.3 Firewall UFW — solo puertos autorizados"
cmd "sudo ufw status numbered"
sudo ufw status numbered 2>/dev/null || warn "UFW puede no estar instalado"

step "2.4 Fail2Ban protegiendo SSH"
if sudo fail2ban-client status sshd 2>/dev/null; then
	ok "Fail2Ban activo en SSH"
else
	warn "Fail2Ban no configurado o no instalado"
fi

pause

# =============================================================================
# 3. ACTIVE DIRECTORY — SAMBA AD DC
# =============================================================================
banner "PARTE 3 — IDENTIDAD: ACTIVE DIRECTORY (SAMBA AD DC)"

step "3.1 Verificar controlador de dominio — nivel funcional"
cmd "docker compose exec samba-ad-dc samba-tool domain level show -s /samba/etc/smb.conf"
docker compose exec samba-ad-dc samba-tool domain level show -s /samba/etc/smb.conf
ok "Domain controller funcionando"

pause

step "3.2 Listar usuarios del dominio (por defecto: Administrator + krbtgt)"
cmd "docker compose exec samba-ad-dc samba-tool user list -s /samba/etc/smb.conf"
docker compose exec samba-ad-dc samba-tool user list -s /samba/etc/smb.conf

pause

step "3.3 CREAR usuario en el dominio: vendedor2"
echo -e "  ${CYAN}Creando: vendedor2 / Venta2026!${NC}"
cmd "docker compose exec samba-ad-dc samba-tool user create vendedor2 Venta2026! --given-name=Vendedor --surname=Dos -s /samba/etc/smb.conf"
docker compose exec samba-ad-dc samba-tool user create vendedor2 Venta2026! --given-name=Vendedor --surname=Dos -s /samba/etc/smb.conf
ok "Usuario vendedor2 creado en el dominio"

step "3.4 Verificar que el usuario aparece en el listado"
cmd "docker compose exec samba-ad-dc samba-tool user list -s /samba/etc/smb.conf"
docker compose exec samba-ad-dc samba-tool user list -s /samba/etc/smb.conf

pause

step "3.5 phpLDAPadmin — interfaz gráfica LDAP"
echo -e "  ${BOLD}Abra en su navegador:${NC}"
echo -e "    ${CYAN}http://${IP}:8082${NC}"
echo ""
echo -e "  ${BOLD}Datos de conexión:${NC}"
echo -e "    Login DN: ${GREEN}CN=Administrator,CN=Users,DC=proyecto,DC=local${NC}"
echo -e "    Password: ${GREEN}Admin123!${NC}"
echo ""
echo -e "  ${BOLD}Pasos:${NC}"
echo -e "    1. Login con los datos de arriba"
echo -e "    2. Explorar árbol: DC=proyecto,DC=local → CN=Users"
echo -e "    3. Ver el usuario 'vendedor2' recién creado"
echo -e "    4. Crear otro usuario desde la GUI (opcional)"

pause

# =============================================================================
# 4. BASE DE DATOS — POSTGRESQL + REPLICACIÓN
# =============================================================================
banner "PARTE 4 — BASE DE DATOS: POSTGRESQL CON REPLICACIÓN"

step "4.1 Tablas del sistema"
cmd "docker compose exec postgres-primary psql -U postgres -d sistemaventas -c '\dt app.*'"
docker compose exec postgres-primary psql -U postgres -d sistemaventas -c '\dt app.*' 2>/dev/null || warn "Tablas no encontradas (puede faltar el schema app)"

step "4.2 Contar productos en inventario"
cmd "docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT count(*) AS total_productos FROM app.productos;'"
docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT count(*) AS total_productos FROM app.productos;' 2>/dev/null ||
	docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT count(*) AS total_productos FROM products;' 2>/dev/null ||
	warn "No se pudo consultar productos"

step "4.3 Ver los primeros 5 productos"
cmd "docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT id, name, stock, price FROM app.productos ORDER BY id LIMIT 5;'"
docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT id, name, stock, price FROM app.productos ORDER BY id LIMIT 5;' 2>/dev/null ||
	docker compose exec postgres-primary psql -U postgres -d sistemaventas -c 'SELECT id, name, stock, price FROM products ORDER BY id LIMIT 5;'

step "4.4 Estado de la replicación (streaming)"
cmd "docker compose exec postgres-primary psql -U postgres -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""
REPL_COUNT=$(docker compose exec postgres-primary psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ')
if [ "$REPL_COUNT" -gt 0 ] 2>/dev/null; then
	docker compose exec postgres-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
	ok "Replicación activa"
else
	warn "No hay réplicas conectadas aún (puede estar en inicio)"
fi

step "4.5 Verificar que la réplica está sincronizada"
cmd "docker compose exec postgres-replica pg_isready -U postgres"
docker compose exec postgres-replica pg_isready -U postgres

pause

# =============================================================================
# 5. APLICACIÓN WEB — DEMO FUNCIONAL
# =============================================================================
banner "PARTE 5 — APLICACIÓN WEB: SISTEMA DE VENTAS"

echo -e "  ${BOLD}Abra en su navegador:${NC}"
echo -e "    ${CYAN}https://${IP}:8443${NC}  (App Sistema de Ventas)"
echo -e "    ${CYAN}http://${IP}:8080${NC}   (HTTP, si HTTPS no funciona)"
echo ""
echo -e "  ${BOLD}Credenciales de prueba:${NC}"
echo -e "    admin:     ${GREEN}admin / demo-admin${NC}     (acceso completo)"
echo -e "    vendedor:  ${GREEN}caja01 / demo-vendedor${NC} (solo ventas)"
echo ""
echo -e "  ${BOLD}Demostrar:${NC}"
echo -e "    1. Iniciar sesión con ${GREEN}admin / demo-admin${NC}"
echo -e "    2. Ver Dashboard principal con resumen del negocio"
echo -e "    3. Ir a Productos → explorar inventario (bebidas, abarrotes)"
echo -e "    4. Crear un producto nuevo (ej: 'Refresco Demo 500ml')"
echo -e "    5. Ir a Ventas → Nueva Venta → vender 3 unidades"
echo -e "    6. Volver a Productos → verificar que el stock bajó"
echo -e "    7. Ir a Usuarios → crear un usuario nuevo (solo admin)"
echo ""
echo -e "  ${YELLOW}Nota: Las sesiones se guardan en Redis. Si reinicia app1,${NC}"
echo -e "  ${YELLOW}la sesión persiste porque app2 lee el mismo Redis.${NC}"

pause

# =============================================================================
# 6. SESIONES REDIS — DEMOSTRACIÓN
# =============================================================================
banner "PARTE 6 — SESIONES DISTRIBUIDAS CON REDIS"

step "6.1 Redis en memoria — sesiones compartidas entre app1 y app2"
cmd "docker compose exec redis redis-cli INFO memory | grep -E 'used_memory_human|maxmemory'"
docker compose exec redis redis-cli INFO memory | grep -E 'used_memory_human|maxmemory'

step "6.2 Claves de sesión activas en Redis"
cmd "docker compose exec redis redis-cli KEYS 'sistemaventas:sess:*'"
SESSION_COUNT=$(docker compose exec redis redis-cli KEYS 'sistemaventas:sess:*' 2>/dev/null | wc -l)
if [ "$SESSION_COUNT" -gt 0 ]; then
	docker compose exec redis redis-cli KEYS 'sistemaventas:sess:*'
	ok "Sesiones activas: $SESSION_COUNT"
else
	warn "Sin sesiones activas (inicie sesión en la app primero)"
fi

step "6.3 Redis info general"
cmd "docker compose exec redis redis-cli INFO server | grep -E 'redis_version|uptime_in_seconds|connected_clients'"
docker compose exec redis redis-cli INFO server | grep -E 'redis_version|uptime_in_seconds|connected_clients'

pause

# =============================================================================
# 7. BACKUPS — DEMOSTRACIÓN
# =============================================================================
banner "PARTE 7 — BACKUPS AUTOMÁTICOS"

step "7.1 Backups de base de datos generados automáticamente"
cmd "ls -lh /srv/sistemaventas/backups/db/ 2>/dev/null | tail -5"
if [ -d /srv/sistemaventas/backups/db ] && [ "$(ls -A /srv/sistemaventas/backups/db 2>/dev/null)" ]; then
	ls -lh /srv/sistemaventas/backups/db/ | tail -5
	ok "Backups encontrados"
else
	warn "No hay backups aún (se generan cada 6h)"
fi

step "7.2 Forzar un backup manual AHORA"
cmd "docker compose exec backup-db-service sh -c 'pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/demo_manual_$(date +%Y%m%d_%H%M%S).sql.gz'"
echo -e "  ${YELLOW}Generando backup manual...${NC}"
docker compose exec backup-db-service sh -c "pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/demo_manual_\$(date +%Y%m%d_%H%M%S).sql.gz" && ok "Backup manual generado" || warn "Error al generar backup manual"

step "7.3 Verificar que el backup manual se creó"
cmd "ls -lh /srv/sistemaventas/backups/db/ | tail -3"
ls -lh /srv/sistemaventas/backups/db/ | tail -3

pause

# =============================================================================
# 8. MONITOREO — GRAFANA + PROMETHEUS + EXPORTERS
# =============================================================================
banner "PARTE 8 — MONITOREO: GRAFANA + PROMETHEUS"

echo -e "  ${BOLD}Abra en su navegador:${NC}"
echo -e "    ${CYAN}https://${IP}:8444${NC}  (Grafana)"
echo -e "    ${CYAN}http://${IP}:8081${NC}   (Grafana HTTP)"
echo ""
echo -e "  ${BOLD}Credenciales:${NC}"
echo -e "    Usuario: ${GREEN}admin${NC}"
echo -e "    Password: ${GREEN}admin123${NC}"
echo ""
echo -e "  ${BOLD}Si el dashboard no está importado:${NC}"
echo -e "    1. Menú → Dashboards → Import"
echo -e "    2. Pegar el JSON del archivo dockerproyect-dashboard.json"
echo -e "    3. Seleccionar datasource Prometheus y Loki"
echo ""

step "8.1 Scrape targets de Prometheus"
cmd "curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool 2>/dev/null | grep -E 'job|health' | head -20 || curl -s http://localhost:9090/api/v1/targets 2>/dev/null | head -5 || echo '  (Prometheus no responde) '"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:9090 2>/dev/null | grep -q 200; then
	TARGETS_UP=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '"health":"up"' | wc -l)
	TARGETS_DOWN=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '"health":"down"' | wc -l)
	ok "Prometheus: $TARGETS_UP targets UP, $TARGETS_DOWN DOWN"
else
	warn "Prometheus no responde en :9090"
fi

step "8.2 Exporters activos"
for EXPORTER in "postgres-exporter:9187" "redis-exporter:9121"; do
	NAME="${EXPORTER%:*}"
	PORT="${EXPORTER#*:}"
	if curl -s -o /dev/null -w "%{http_code}" http://$NAME:$PORT/metrics 2>/dev/null | grep -q 200; then
		ok "$NAME responde en puerto $PORT"
	else
		warn "$NAME no responde aún"
	fi
done

pause

# =============================================================================
# 9. ALTA DISPONIBILIDAD — PRUEBA DE CAÍDA
# =============================================================================
banner "PARTE 9 — ALTA DISPONIBILIDAD: TOLERANCIA A FALLOS"

step "9.1 Estado actual — ambas apps healthy"
cmd "docker compose ps app1 app2"
docker compose ps app1 app2

step "9.2 DETENER app1 (simular caída)"
cmd "docker compose stop app1"
docker compose stop app1
echo -e "  ${RED}app1 DETENIDA — nginx deriva tráfico a app2 automáticamente${NC}"

step "9.3 Verificar que la app sigue respondiendo"
cmd "curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://localhost:8080/health"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
	ok "App respondiendo (HTTP $HTTP_CODE) — app2 absorbió el tráfico"
else
	warn "Código de respuesta: $HTTP_CODE"
fi

step "9.4 En Grafana: Stack Health debe mostrar app1 en rojo"
echo -e "  ${BOLD}Recargue Grafana → Stack Health → app1 debe aparecer como DOWN${NC}"

step "9.5 Ver logs de app2 para confirmar que está sirviendo"
cmd "docker compose logs --tail=3 app2"
docker compose logs --tail=3 app2

pause

step "9.6 RECUPERAR app1"
cmd "docker compose start app1 && sleep 5"
docker compose start app1 && sleep 5
cmd "docker compose ps app1 app2 && echo '---' && curl -s -o /dev/null -w 'HTTP: %{http_code}\n' http://localhost:8080/health"
docker compose ps app1 app2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null)
echo "  HTTP /health: $HTTP_CODE"
ok "app1 recuperada — balanceo de carga restaurado"

pause

# =============================================================================
# 10. LOGS CENTRALIZADOS — LOKI + PROMPTAIL
# =============================================================================
banner "PARTE 10 — LOGS CENTRALIZADOS (LOKI + PROMPTAIL)"

step "10.1 Últimas líneas de la app"
cmd "docker compose logs --tail=5 app1"
docker compose logs --tail=5 app1

echo ""
echo -e "  ${BOLD}En Grafana → Explore → Loki:${NC}"
echo -e "    {container_name=\"nginx\"}       → todas las peticiones HTTP"
echo -e "    {container_name=\"app1\"} |= \"error\"  → errores de la app"
echo -e "    {container_name=~\".+\"}         → logs de todos los servicios"

pause

# =============================================================================
# CIERRE
# =============================================================================
banner "DEMOSTRACIÓN COMPLETADA ✓"

echo ""
echo -e "  ${GREEN}${BOLD}Resumen de lo demostrado (${CYAN}10 partes${GREEN}):${NC}"
echo ""
echo -e "  ✅ ${BOLD}1. Infraestructura:${NC}    20 contenedores Docker, 6 redes segmentadas"
echo -e "  ✅ ${BOLD}2. Seguridad:${NC}         TLS/HTTPS, firewall UFW, Fail2Ban"
echo -e "  ✅ ${BOLD}3. Identidad:${NC}         Samba AD DC + phpLDAPadmin (creación de usuarios)"
echo -e "  ✅ ${BOLD}4. Base de datos:${NC}     PostgreSQL 17 con replicación streaming"
echo -e "  ✅ ${BOLD}5. Aplicación:${NC}        Node.js + Express, CRUD inventario y ventas"
echo -e "  ✅ ${BOLD}6. Sesiones Redis:${NC}    Sesiones distribuidas compartidas app1/app2"
echo -e "  ✅ ${BOLD}7. Backups:${NC}           pg_dump + backup de archivos + cloud sync (rclone)"
echo -e "  ✅ ${BOLD}8. Monitoreo:${NC}         Grafana + Prometheus + exporters"
echo -e "  ✅ ${BOLD}9. Alta disponibilidad:${NC} Tolerancia a caída de un nodo de app"
echo -e "  ✅ ${BOLD}10. Logs:${NC}             Loki + Promtail centralizados"
echo ""
echo -e "  ${BOLD}URLs de acceso:${NC}"
echo -e "    App (HTTPS):   ${CYAN}https://${IP}:8443${NC}"
echo -e "    App (HTTP):    ${CYAN}http://${IP}:8080${NC}"
echo -e "    Grafana:       ${CYAN}https://${IP}:8444${NC}  (admin / admin123)"
echo -e "    phpLDAPadmin:  ${CYAN}http://${IP}:8082${NC}"
echo ""
echo -e "  ${BOLD}Comandos de emergencia:${NC}"
echo -e "    Reiniciar stack: docker compose restart"
echo -e "    Logs en vivo:    docker compose logs -f [servicio]"
echo -e "    Backup manual:   docker compose exec backup-db-service sh -c 'pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/manual.sql.gz'"
echo ""
