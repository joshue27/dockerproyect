# Sistema Ventas

Base inicial del MVP academico construida con Node.js, Express, EJS y PostgreSQL.

## Estructura

- `src/app.js`: configura Express, middlewares, vistas y manejo de errores.
- `src/server.js`: punto de entrada que levanta el servidor.
- `src/config/env.js`: centraliza variables de entorno.
- `src/db/pool.js`: crea el pool de conexiones a PostgreSQL.
- `src/routes/web.js`: define las rutas web.
- `src/controllers/`: coordina la logica HTTP.
- `src/repositories/`: encapsula consultas SQL.
- `src/views/`: plantillas EJS renderizadas del lado del servidor.
- `database/init/`: scripts SQL de inicializacion.

## Rutas iniciales

- `/`: dashboard
- `/productos`: listado de productos
- `/health`: healthcheck

## Siguiente paso recomendado

1. instalar dependencias con `npm install`
2. copiar `.env.example` a `.env`
3. levantar PostgreSQL
4. ejecutar la app

## PostgreSQL con Docker

### 1. Levantar la base

```bash
docker compose up -d
```

### 2. Verificar contenedor

```bash
docker compose ps
docker compose logs postgres
```

### 3. Importante sobre el script SQL

El archivo `database/init/01_minimo_bebidas_abarrotes.sql` se ejecuta automaticamente
solo la primera vez que PostgreSQL inicializa el volumen de datos.

Si queres reinicializar desde cero:

```bash
docker compose down -v
docker compose up -d
```

### 4. Conexion esperada para la app local

La app Node corriendo en tu maquina usa:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sistemaventas
```
