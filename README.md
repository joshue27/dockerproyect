# Sistema de Ventas — Bebidas y Abarrotes S.A.

MVP académico de gestión comercial con arquitectura Docker multi-servicio.
App Node.js + Express con sesiones en Redis, PostgreSQL en alta disponibilidad, Samba AD DC como controlador de dominio, backups automatizados y stack completo de observabilidad.

---

## Quick start (Alma Linux / RHEL)

En una VM Alma Linux 8.x o 9.x recién instalada, ejecutá como **root**:

```bash
curl -fsSL https://raw.githubusercontent.com/joshue27/dockerproyect/main/bootstrap-almalinux.sh | sudo bash
```

Eso clona el repo, instala Docker CE, configura firewall, SELinux, levanta el stack y te muestra las URLs.

**Requisitos mínimos:** 4 vCPU · 8 GB RAM · 40 GB disco · Acceso a internet

### ¿Tenés ≤ 6 GB de RAM? (demo académica)

El instalador **detecta RAM baja y configura swap de 4 GB automáticamente**.
Además, el repo incluye `docker-compose.override.yml` con:

- Límites de memoria por contenedor (ninguno acapara todo)
- PostgreSQL con `shared_buffers=128MB`
- Redis con `maxmemory=64mb`
- Prometheus con retención reducida a 3 días / 500 MB
- Backups cada 24h (no se disparan durante la demo)

El override se aplica **automáticamente** por Docker Compose — no tenés que hacer nada.
Levantá el stack 5-10 minutos antes de la demo, dejá que estabilice, y mostrás.

---

## Acceso rápido

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| **App** | `http://<IP>:8080` | — |
| **Grafana** | `http://<IP>:8081` | `admin` / `admin123` |
| **Samba AD DC** | CLI / RSAT | `Administrator` / `Admin123!` |

> Las credenciales por defecto van en `.env`. **Cambialas antes de producción.**

---

## Servicios

| Servicio | Imagen | Rol |
|----------|--------|-----|
| **nginx** | `nginx:1.27-alpine` | Reverse proxy + load balancer entre app1 y app2 |
| **app1 / app2** | `sistemaventas-app:local` | Node.js 20, Express 5, EJS. Sesiones compartidas en Redis |
| **redis** | `redis:7-alpine` | Session store (`connect-redis`). Persistencia AOF |
| **postgres-primary** | `postgres:17-alpine` | PostgreSQL con `wal_level=replica`, 10 replication slots |
| **postgres-replica** | `postgres:17-alpine` | Réplica streaming. Hot standby |
| **samba-ad-dc** | `sistemaventas-samba:local` (build local) | Active Directory Domain Controller con entrypoint fixeado (debug provisioning) |
| **backup-db-service** | `postgres:17-alpine` | Backup automático de BD cada 6h. Retención 7 días |
| **backup-files-service** | `alpine:3.20` | Backup de archivos de la app. Misma frecuencia y retención |
| **rclone-sync** | `rclone/rclone` | Sincronización cloud de backups (Google Drive por defecto) |
| **prometheus** | `prom/prometheus` | Métricas del stack |
| **grafana** | `grafana/grafana-oss` | Dashboards y visualización |
| **loki** | `grafana/loki` | Agregación de logs |
| **promtail** | `grafana/promtail` | Recolección de logs de contenedores |
| **postgres-exporter** | `prometheuscommunity/postgres-exporter` | Métricas de PostgreSQL |
| **redis-exporter** | `oliver006/redis_exporter` | Métricas de Redis |

---

## Redes

El stack usa 6 redes bridge segmentadas por capa:

| Red | Alcance | Servicios |
|-----|---------|-----------|
| `edge_net` | Expuesta | nginx, samba-ad-dc |
| `app_net` | Interna | nginx, app1, app2, redis, backup-files-service, redis-exporter |
| `data_net` | Interna | app1, app2, postgres-primary, postgres-replica, backup-db-service, rclone-sync, postgres-exporter |
| `identity_net` | Interna | samba-ad-dc |
| `admin_net` | Interna | nginx, prometheus, grafana |
| `observability_net` | Interna | redis, postgres-primary, postgres-replica, prometheus, grafana, loki, promtail, postgres-exporter, redis-exporter |

---

## Estructura del proyecto

```
dockerproyect/
├── docker-compose.yml              # Stack principal
├── docker-compose.env.example      # Variables de entorno de referencia
├── .env                            # Variables de entorno (no versionado)
├── bootstrap-almalinux.sh          # Un solo script: clona e instala todo
├── install-almalinux.sh            # Instalador completo (16 pasos)
│
├── nginx/
│   └── nginx.conf                  # Reverse proxy: app (80) + Grafana (81)
│
├── sistemaventas/                  # Aplicación Node.js
│   ├── Dockerfile
│   ├── package.json
│   ├── src/
│   │   ├── app.js                  # Configuración Express
│   │   ├── server.js               # Punto de entrada
│   │   ├── config/env.js           # Variables de entorno
│   │   ├── config/redis.js         # Conexión Redis (session store)
│   │   ├── routes/web.js           # Rutas web
│   │   └── views/                  # Plantillas EJS
│   └── database/init/              # Scripts SQL de inicialización
│
├── database/
│   └── postgres/
│       ├── primary/
│       │   ├── init/02_replication_user.sh
│       │   └── pg_hba.conf
│       └── replica/
│           └── replica-entrypoint.sh
│
├── backups/
│   ├── backup-db.sh                # Loop de pg_dump + gzip
│   ├── backup-files.sh             # Loop de tar + gzip
│   └── rclone-sync.sh              # Sincronización cloud
│
├── ops/
│   ├── prometheus/prometheus.yml
│   ├── loki/config.yml
│   ├── promtail/config.yml
│   └── grafana/provisioning/
│       └── datasources/
│
└── ldap/                           # (preparado para extensión LDAP)
```

---

## Configuración

### Variables de entorno (`.env`)

| Variable | Default | Descripción |
|----------|---------|-------------|
| `APP_PORT` | `8080` | Puerto público de la aplicación |
| `GRAFANA_PORT` | `8081` | Puerto público de Grafana |
| `POSTGRES_USER` | `postgres` | Usuario de PostgreSQL |
| `POSTGRES_PASSWORD` | `postgres` | **Cambiar** — contraseña de PostgreSQL |
| `POSTGRES_DB` | `sistemaventas` | Nombre de la base de datos |
| `REPLICATION_USER` | `replicator` | Usuario de replicación |
| `REPLICATION_PASSWORD` | `replicator123` | **Cambiar** — contraseña de replicación |
| `SESSION_SECRET` | `demo-session-secret` | **Cambiar** — secreto de sesiones Express |
| `SAMBA_DOMAIN` | `proyecto.local` | Dominio del AD |
| `SAMBA_HOST_IP` | `172.20.0.10` | IP estática del contenedor Samba en identity_net |
| `SAMBA_NET_SUBNET` | `172.20.0.0/24` | Subred de identity_net |
| `SAMBA_ADMIN_PASSWORD` | `Admin123!` | **Cambiar** — contraseña del Administrator de AD |
| `GRAFANA_ADMIN_PASSWORD` | `admin123` | **Cambiar** — contraseña de Grafana |
| `DB_BACKUP_INTERVAL_SECONDS` | `21600` | Frecuencia de backup de BD (6h) |
| `RCLONE_REMOTE_NAME` | `gdrive` | Remote configurado en rclone |

> Copiá `docker-compose.env.example` a `.env` y editá las contraseñas antes de levantar.

---

## Instalación manual

Si preferís hacerlo paso a paso en lugar del script automático:

### Alma Linux

```bash
# 1. Clonar
git clone https://github.com/joshue27/dockerproyect.git
cd dockerproyect

# 2. Instalar dependencias
sudo dnf install -y dnf-plugins-core curl git
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# 3. Configurar firewall
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
# ... y los 14 puertos de Samba AD DC (ver install-almalinux.sh)
sudo firewall-cmd --reload

# 4. Configurar .env
cp docker-compose.env.example .env
# Editar contraseñas: nano .env

# 5. Levantar
docker compose up -d
```

### Ubuntu Server

```bash
# Mismos pasos, pero usando apt:
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## Comandos útiles

```bash
# Ver estado
docker compose ps

# Logs de todo el stack
docker compose logs -f

# Logs de un servicio
docker compose logs -f app1

# Reiniciar un servicio
docker compose restart nginx

# Bajar el stack
docker compose down

# Bajar TODO (incluyendo volúmenes — ¡pierde datos!)
docker compose down -v

# Validar compose
docker compose config

# Backup manual de BD
docker compose exec backup-db-service sh -c \
  'pg_dump -h postgres-primary -U postgres -d sistemaventas | gzip > /backups/db/manual.sql.gz'

# Ver backups generados
ls -la /srv/sistemaventas/backups/db/

# Acceder al contenedor de Samba
docker compose exec samba-ad-dc bash
```

---

## Dominio Active Directory

### Crear usuarios

```bash
docker compose exec samba-ad-dc samba-tool user create jperez Password123!
```

### Unir una VM Linux cliente al dominio

```bash
# En la VM cliente (Alma Linux / Ubuntu):
sudo dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common-tools
sudo realm discover proyecto.local
sudo realm join proyecto.local -U Administrator
```

### Puertos expuestos por Samba AD DC

| Puerto | Protocolo | Servicio |
|--------|-----------|----------|
| 53 | TCP/UDP | DNS |
| 88 | TCP/UDP | Kerberos |
| 135 | TCP | RPC Endpoint Mapper |
| 389 | TCP/UDP | LDAP |
| 445 | TCP | SMB |
| 464 | TCP/UDP | Kerberos (cambio de contraseña) |
| 636 | TCP | LDAPS |
| 3268 | TCP | Global Catalog |
| 3269 | TCP | Global Catalog SSL |
| 50000-50050 | TCP | RPC dinámico |

---

## Monitoreo

### Dashboards sugeridos en Grafana

- **ATL — Overview**: estado general del stack (`up`, `count(up) - sum(up)`)
- **ATL — PostgreSQL**: conexiones, locks, replicación
- **ATL — Redis**: memoria, comandos, conexiones
- **ATL — Logs**: logs agregados vía Loki

### Queries rápidas en Explore

```promql
# Servicios activos
up

# Solo PostgreSQL
up{job="postgres_exporter"}

# Servicios caídos
count(up) - sum(up)
```

---

## Backups

Los backups son **automáticos** y arrancan ni bien levanta el stack:

| Tipo | Frecuencia | Retención | Ubicación |
|------|-----------|-----------|-----------|
| Base de datos | Cada 6h | 7 días | `/srv/sistemaventas/backups/db/*.sql.gz` |
| Archivos de app | Cada 6h | 7 días | `/srv/sistemaventas/backups/files/*.tar.gz` |
| Sincronización cloud | Cada 15 min | — | Configurable vía rclone |

### Configurar rclone (Google Drive, S3, etc.)

```bash
docker run --rm -it -v /srv/sistemaventas/rclone:/config/rclone rclone/rclone config
```

Luego ajustá `RCLONE_REMOTE_NAME` y `RCLONE_REMOTE_PATH` en `.env`.

---

## Stack técnico

| Capa | Tecnología |
|------|-----------|
| **Runtime** | Node.js 20 (Alpine) |
| **Framework** | Express 5 |
| **Vistas** | EJS (server-side rendering) |
| **Base de datos** | PostgreSQL 17 con replicación streaming |
| **Sesiones** | Redis 7 (`connect-redis`, `express-session`) |
| **Proxy** | Nginx 1.27 (least_conn load balancing) |
| **Identidad** | Samba AD DC (Active Directory) |
| **Métricas** | Prometheus + PostgreSQL Exporter + Redis Exporter |
| **Logs** | Loki + Promtail |
| **Dashboards** | Grafana OSS |
| **Backups** | pg_dump + tar + rclone (cloud sync) |
| **Contenedores** | Docker + Docker Compose |

---

## Requisitos

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 4 vCPU | 6 vCPU |
| RAM | 8 GB | 12-16 GB |
| Disco | 40 GB | 60 GB |
| SO | Alma Linux 8/9 · Rocky Linux 8/9 · Ubuntu Server 22.04/24.04 |
| Docker | Engine 24+ · Compose v2 |
