-- =========================================================
-- Sistema mínimo: Bebidas y Abarrotes S.A.
-- Motor objetivo: PostgreSQL
-- Propósito: MVP académico con datos semilla
-- =========================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS app;

SET search_path TO app, public;

-- =========================================================
-- Catálogos
-- =========================================================

CREATE TABLE IF NOT EXISTS roles (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS request_statuses (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(30) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS request_types (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS financial_movement_types (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(20) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_financial_movement_type
        CHECK (name IN ('income', 'expense'))
);

CREATE TABLE IF NOT EXISTS inventory_movement_types (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(20) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_inventory_movement_type
        CHECK (name IN ('in', 'out'))
);

-- =========================================================
-- Seguridad / usuarios
-- =========================================================

CREATE TABLE IF NOT EXISTS users (
    id              BIGSERIAL PRIMARY KEY,
    role_id         BIGINT NOT NULL REFERENCES roles(id),
    username        VARCHAR(50) NOT NULL UNIQUE,
    full_name       VARCHAR(120) NOT NULL,
    email           VARCHAR(150) UNIQUE,
    password_hash   TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- Inventario
-- =========================================================

CREATE TABLE IF NOT EXISTS products (
    id              BIGSERIAL PRIMARY KEY,
    sku             VARCHAR(30) NOT NULL UNIQUE,
    name            VARCHAR(120) NOT NULL,
    description     TEXT,
    price           NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    stock           INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_stock       INTEGER NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory_movements (
    id                  BIGSERIAL PRIMARY KEY,
    product_id          BIGINT NOT NULL REFERENCES products(id),
    movement_type_id    BIGINT NOT NULL REFERENCES inventory_movement_types(id),
    quantity            INTEGER NOT NULL CHECK (quantity > 0),
    reason              VARCHAR(150) NOT NULL,
    created_by          BIGINT NOT NULL REFERENCES users(id),
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- Ventas
-- =========================================================

CREATE TABLE IF NOT EXISTS sales (
    id              BIGSERIAL PRIMARY KEY,
    sale_number     VARCHAR(30) NOT NULL UNIQUE,
    user_id         BIGINT NOT NULL REFERENCES users(id),
    customer_name   VARCHAR(120),
    discount        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    total           NUMERIC(12,2) NOT NULL CHECK (total >= 0),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sale_items (
    id              BIGSERIAL PRIMARY KEY,
    sale_id         BIGINT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id      BIGINT NOT NULL REFERENCES products(id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    subtotal        NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0)
);

-- =========================================================
-- Atención al cliente
-- =========================================================

CREATE TABLE IF NOT EXISTS customer_requests (
    id                  BIGSERIAL PRIMARY KEY,
    request_type_id     BIGINT NOT NULL REFERENCES request_types(id),
    status_id           BIGINT NOT NULL REFERENCES request_statuses(id),
    customer_name       VARCHAR(120) NOT NULL,
    contact_phone       VARCHAR(30),
    description         TEXT NOT NULL,
    created_by          BIGINT NOT NULL REFERENCES users(id),
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- Finanzas
-- =========================================================

CREATE TABLE IF NOT EXISTS financial_movements (
    id                  BIGSERIAL PRIMARY KEY,
    movement_type_id    BIGINT NOT NULL REFERENCES financial_movement_types(id),
    concept             VARCHAR(150) NOT NULL,
    amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    reference_table     VARCHAR(50),
    reference_id        BIGINT,
    created_by          BIGINT NOT NULL REFERENCES users(id),
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- Índices mínimos
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_products_active ON products(active);
CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_product ON inventory_movements(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_user ON sales(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_customer_requests_status ON customer_requests(status_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_financial_movements_type ON financial_movements(movement_type_id, created_at DESC);

-- =========================================================
-- Datos semilla
-- =========================================================

INSERT INTO roles (name)
VALUES
    ('admin'),
    ('vendedor'),
    ('bodega')
ON CONFLICT (name) DO NOTHING;

INSERT INTO request_statuses (name)
VALUES
    ('pendiente'),
    ('en_proceso'),
    ('resuelto')
ON CONFLICT (name) DO NOTHING;

INSERT INTO request_types (name)
VALUES
    ('pedido_especial'),
    ('consulta_producto'),
    ('reclamo')
ON CONFLICT (name) DO NOTHING;

INSERT INTO financial_movement_types (name)
VALUES
    ('income'),
    ('expense')
ON CONFLICT (name) DO NOTHING;

INSERT INTO inventory_movement_types (name)
VALUES
    ('in'),
    ('out')
ON CONFLICT (name) DO NOTHING;

-- Usuarios de ejemplo
INSERT INTO users (role_id, username, full_name, email, password_hash)
SELECT r.id, v.username, v.full_name, v.email, v.password_hash
FROM (
    VALUES
        ('admin',    'admin',    'Ana López',    'ana@bebidas.local',   'demo-admin'),
        ('vendedor', 'caja01',   'Carlos Pérez', 'carlos@bebidas.local','demo-vendedor'),
        ('bodega',   'bodega01', 'María Gómez',  'maria@bebidas.local', 'demo-bodega')
) AS v(role_name, username, full_name, email, password_hash)
JOIN roles r ON r.name = v.role_name
ON CONFLICT (username) DO NOTHING;

-- Productos de ejemplo
INSERT INTO products (sku, name, description, price, stock, min_stock)
VALUES
    ('BEB-001', 'Coca Cola 2L', 'Bebida carbonatada de 2 litros', 12.50, 40, 10),
    ('BEB-002', 'Agua Purificada 1L', 'Botella de agua purificada', 5.00, 25, 8),
    ('ABA-001', 'Arroz 1kg', 'Paquete de arroz blanco de 1 kilogramo', 9.75, 15, 5)
ON CONFLICT (sku) DO NOTHING;

-- Movimientos iniciales de inventario
INSERT INTO inventory_movements (product_id, movement_type_id, quantity, reason, created_by)
SELECT p.id, imt.id, v.quantity, v.reason, u.id
FROM (
    VALUES
        ('BEB-001', 'in', 40, 'Carga inicial'),
        ('BEB-002', 'in', 25, 'Carga inicial'),
        ('ABA-001', 'in', 15, 'Carga inicial')
) AS v(sku, movement_type, quantity, reason)
JOIN products p ON p.sku = v.sku
JOIN inventory_movement_types imt ON imt.name = v.movement_type
JOIN users u ON u.username = 'bodega01'
WHERE NOT EXISTS (
    SELECT 1
    FROM inventory_movements x
    WHERE x.product_id = p.id
      AND x.reason = v.reason
);

-- Ventas de ejemplo
INSERT INTO sales (sale_number, user_id, customer_name, discount, total, created_at)
SELECT v.sale_number, u.id, v.customer_name, v.discount, v.total, v.created_at
FROM (
    VALUES
        ('VTA-0001', 'caja01', 'Juan Ramírez', 0.00, 25.00, CURRENT_TIMESTAMP - INTERVAL '2 day'),
        ('VTA-0002', 'caja01', 'Lucía Morales', 1.50, 18.00, CURRENT_TIMESTAMP - INTERVAL '1 day'),
        ('VTA-0003', 'admin',  'Pedro Castillo', 0.00, 19.50, CURRENT_TIMESTAMP)
) AS v(sale_number, username, customer_name, discount, total, created_at)
JOIN users u ON u.username = v.username
ON CONFLICT (sale_number) DO NOTHING;

INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
SELECT s.id, p.id, v.quantity, v.unit_price, v.subtotal
FROM (
    VALUES
        ('VTA-0001', 'BEB-001', 2, 12.50, 25.00),
        ('VTA-0002', 'BEB-002', 3, 5.00, 15.00),
        ('VTA-0002', 'ABA-001', 1, 4.50, 4.50),
        ('VTA-0003', 'ABA-001', 2, 9.75, 19.50)
) AS v(sale_number, sku, quantity, unit_price, subtotal)
JOIN sales s ON s.sale_number = v.sale_number
JOIN products p ON p.sku = v.sku
WHERE NOT EXISTS (
    SELECT 1
    FROM sale_items si
    WHERE si.sale_id = s.id
      AND si.product_id = p.id
);

-- Ajuste de stock después de ventas demo
UPDATE products p
SET stock = src.new_stock,
    updated_at = CURRENT_TIMESTAMP
FROM (
    VALUES
        ('BEB-001', 38),
        ('BEB-002', 22),
        ('ABA-001', 12)
) AS src(sku, new_stock)
WHERE p.sku = src.sku;

INSERT INTO inventory_movements (product_id, movement_type_id, quantity, reason, created_by, created_at)
SELECT p.id, imt.id, v.quantity, v.reason, u.id, v.created_at
FROM (
    VALUES
        ('BEB-001', 'out', 2, 'Venta demo VTA-0001', CURRENT_TIMESTAMP - INTERVAL '2 day'),
        ('BEB-002', 'out', 3, 'Venta demo VTA-0002', CURRENT_TIMESTAMP - INTERVAL '1 day'),
        ('ABA-001', 'out', 3, 'Ventas demo VTA-0002 y VTA-0003', CURRENT_TIMESTAMP)
) AS v(sku, movement_type, quantity, reason, created_at)
JOIN products p ON p.sku = v.sku
JOIN inventory_movement_types imt ON imt.name = v.movement_type
JOIN users u ON u.username = 'caja01'
WHERE NOT EXISTS (
    SELECT 1
    FROM inventory_movements x
    WHERE x.product_id = p.id
      AND x.reason = v.reason
);

-- Solicitudes de clientes de ejemplo
INSERT INTO customer_requests (request_type_id, status_id, customer_name, contact_phone, description, created_by, created_at, updated_at)
SELECT rt.id, rs.id, v.customer_name, v.contact_phone, v.description, u.id, v.created_at, v.updated_at
FROM (
    VALUES
        ('pedido_especial',   'pendiente',   'Tienda El Centro', '5555-1001', 'Solicita 10 cajas de agua purificada para entrega el viernes.', 'caja01',  CURRENT_TIMESTAMP - INTERVAL '2 day', CURRENT_TIMESTAMP - INTERVAL '2 day'),
        ('consulta_producto', 'en_proceso',  'Rosa Mendoza',     '5555-1002', 'Consulta disponibilidad de arroz por mayor.',                  'admin',   CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '12 hour'),
        ('reclamo',           'resuelto',    'Luis Herrera',     '5555-1003', 'Reporta producto dañado en una compra anterior.',             'caja01',  CURRENT_TIMESTAMP - INTERVAL '3 day', CURRENT_TIMESTAMP - INTERVAL '1 day')
 ) AS v(request_type, status_name, customer_name, contact_phone, description, username, created_at, updated_at)
JOIN request_types rt ON rt.name = v.request_type
JOIN request_statuses rs ON rs.name = v.status_name
JOIN users u ON u.username = v.username
WHERE NOT EXISTS (
    SELECT 1
    FROM customer_requests cr
    WHERE cr.customer_name = v.customer_name
      AND cr.description = v.description
);

-- Movimientos financieros de ejemplo
INSERT INTO financial_movements (movement_type_id, concept, amount, reference_table, reference_id, created_by, created_at)
SELECT fmt.id, v.concept, v.amount, v.reference_table, ref.id, u.id, v.created_at
FROM (
    VALUES
        ('income',  'Ingreso por venta VTA-0001', 'sales', 'VTA-0001', 25.00, 'caja01',  CURRENT_TIMESTAMP - INTERVAL '2 day'),
        ('income',  'Ingreso por venta VTA-0002', 'sales', 'VTA-0002', 18.00, 'caja01',  CURRENT_TIMESTAMP - INTERVAL '1 day'),
        ('expense', 'Compra de bolsas para empaque', NULL, NULL, 7.50, 'admin', CURRENT_TIMESTAMP)
) AS v(type_name, concept, reference_table, reference_code, amount, username, created_at)
JOIN financial_movement_types fmt ON fmt.name = v.type_name
JOIN users u ON u.username = v.username
LEFT JOIN sales ref ON ref.sale_number = v.reference_code
WHERE NOT EXISTS (
    SELECT 1
    FROM financial_movements fm
    WHERE fm.concept = v.concept
);

COMMIT;
