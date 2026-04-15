const pool = require('../db/pool');

async function findAll() {
  const query = `
    SELECT
      id,
      sku,
      name,
      description,
      price,
      stock,
      min_stock,
      active,
      created_at,
      updated_at
    FROM app.products
    ORDER BY id ASC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findLowStock() {
  const query = `
    SELECT
      id,
      sku,
      name,
      description,
      price,
      stock,
      min_stock,
      active,
      created_at,
      updated_at
    FROM app.products
    WHERE active = TRUE
      AND stock <= min_stock
    ORDER BY stock ASC, id ASC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findById(id) {
  const query = `
    SELECT
      id,
      sku,
      name,
      description,
      price,
      stock,
      min_stock,
      active,
      created_at,
      updated_at
    FROM app.products
    WHERE id = $1
  `;

  const result = await pool.query(query, [id]);
  return result.rows[0] || null;
}

async function create(product) {
  const query = `
    INSERT INTO app.products (
      sku,
      name,
      description,
      price,
      stock,
      min_stock,
      active
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING id, sku, name, description, price, stock, min_stock, active, created_at, updated_at
  `;

  const values = [
    product.sku,
    product.name,
    product.description,
    product.price,
    product.stock,
    product.minStock,
    product.active
  ];

  const result = await pool.query(query, values);
  return result.rows[0];
}

async function update(id, product) {
  const query = `
    UPDATE app.products
    SET
      sku = $2,
      name = $3,
      description = $4,
      price = $5,
      stock = $6,
      min_stock = $7,
      active = $8,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $1
    RETURNING id, sku, name, description, price, stock, min_stock, active, created_at, updated_at
  `;

  const values = [
    id,
    product.sku,
    product.name,
    product.description,
    product.price,
    product.stock,
    product.minStock,
    product.active
  ];

  const result = await pool.query(query, values);
  return result.rows[0] || null;
}

async function toggleActive(id) {
  const query = `
    UPDATE app.products
    SET
      active = NOT active,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $1
    RETURNING id, sku, name, description, price, stock, min_stock, active, created_at, updated_at
  `;

  const result = await pool.query(query, [id]);
  return result.rows[0] || null;
}

module.exports = {
  findAll,
  findLowStock,
  findById,
  create,
  update,
  toggleActive
};
