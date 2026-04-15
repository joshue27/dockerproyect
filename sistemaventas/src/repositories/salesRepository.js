const pool = require('../db/pool');

async function findAll() {
  const query = `
    SELECT
      s.id,
      s.sale_number,
      s.customer_name,
      s.discount,
      s.total,
      s.created_at,
      u.full_name AS seller_name
    FROM app.sales s
    INNER JOIN app.users u ON u.id = s.user_id
    ORDER BY s.created_at DESC, s.id DESC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findRecent(limit = 5) {
  const query = `
    SELECT
      s.id,
      s.sale_number,
      s.customer_name,
      s.total,
      s.created_at,
      u.full_name AS seller_name
    FROM app.sales s
    INNER JOIN app.users u ON u.id = s.user_id
    ORDER BY s.created_at DESC, s.id DESC
    LIMIT $1
  `;

  const result = await pool.query(query, [limit]);
  return result.rows;
}

async function findById(id) {
  const saleQuery = `
    SELECT
      s.id,
      s.sale_number,
      s.customer_name,
      s.discount,
      s.total,
      s.created_at,
      u.full_name AS seller_name
    FROM app.sales s
    INNER JOIN app.users u ON u.id = s.user_id
    WHERE s.id = $1
  `;

  const itemsQuery = `
    SELECT
      si.id,
      si.quantity,
      si.unit_price,
      si.subtotal,
      p.sku,
      p.name
    FROM app.sale_items si
    INNER JOIN app.products p ON p.id = si.product_id
    WHERE si.sale_id = $1
    ORDER BY si.id ASC
  `;

  const [saleResult, itemsResult] = await Promise.all([
    pool.query(saleQuery, [id]),
    pool.query(itemsQuery, [id])
  ]);

  if (saleResult.rows.length === 0) {
    return null;
  }

  return {
    ...saleResult.rows[0],
    items: itemsResult.rows
  };
}

async function findSellableProducts() {
  const query = `
    SELECT
      id,
      sku,
      name,
      price,
      stock,
      min_stock
    FROM app.products
    WHERE active = TRUE
    ORDER BY name ASC
  `;

  const result = await pool.query(query);
  return result.rows;
}

function generateSaleNumber() {
  const now = new Date();
  const parts = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, '0'),
    String(now.getDate()).padStart(2, '0'),
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
    String(now.getSeconds()).padStart(2, '0')
  ];

  return `VTA-${parts.join('')}`;
}

async function createSale({ customerName, discount, items }) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const sellerResult = await client.query(
      `SELECT id FROM app.users WHERE username = 'caja01' LIMIT 1`
    );

    if (sellerResult.rows.length === 0) {
      throw new Error('No existe el usuario vendedor por defecto (caja01).');
    }

    const sellerId = sellerResult.rows[0].id;

    const productIds = items.map(item => item.productId);
    const productsResult = await client.query(
      `
        SELECT id, name, price, stock
        FROM app.products
        WHERE id = ANY($1::bigint[])
      `,
      [productIds]
    );

    const productsMap = new Map(
      productsResult.rows.map(product => [String(product.id), product])
    );

    let subtotal = 0;
    const normalizedItems = items.map(item => {
      const product = productsMap.get(String(item.productId));

      if (!product) {
        throw new Error('Uno de los productos seleccionados ya no existe.');
      }

      if (item.quantity > product.stock) {
        throw new Error(`No hay stock suficiente para ${product.name}.`);
      }

      const lineSubtotal = Number(product.price) * item.quantity;
      subtotal += lineSubtotal;

      return {
        productId: product.id,
        quantity: item.quantity,
        unitPrice: Number(product.price),
        subtotal: lineSubtotal
      };
    });

    if (discount > subtotal) {
      throw new Error('El descuento no puede ser mayor que el subtotal de la venta.');
    }

    const total = subtotal - discount;
    const saleNumber = generateSaleNumber();

    const saleResult = await client.query(
      `
        INSERT INTO app.sales (
          sale_number,
          user_id,
          customer_name,
          discount,
          total
        )
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
      `,
      [saleNumber, sellerId, customerName, discount, total]
    );

    const saleId = saleResult.rows[0].id;

    const movementTypeResult = await client.query(
      `SELECT id FROM app.inventory_movement_types WHERE name = 'out' LIMIT 1`
    );
    const financialTypeResult = await client.query(
      `SELECT id FROM app.financial_movement_types WHERE name = 'income' LIMIT 1`
    );

    const movementTypeId = movementTypeResult.rows[0]?.id;
    const financialTypeId = financialTypeResult.rows[0]?.id;

    for (const item of normalizedItems) {
      await client.query(
        `
          INSERT INTO app.sale_items (
            sale_id,
            product_id,
            quantity,
            unit_price,
            subtotal
          )
          VALUES ($1, $2, $3, $4, $5)
        `,
        [saleId, item.productId, item.quantity, item.unitPrice, item.subtotal]
      );

      await client.query(
        `
          UPDATE app.products
          SET
            stock = stock - $2,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = $1
        `,
        [item.productId, item.quantity]
      );

      if (movementTypeId) {
        await client.query(
          `
            INSERT INTO app.inventory_movements (
              product_id,
              movement_type_id,
              quantity,
              reason,
              created_by
            )
            VALUES ($1, $2, $3, $4, $5)
          `,
          [item.productId, movementTypeId, item.quantity, `Venta ${saleNumber}`, sellerId]
        );
      }
    }

    if (financialTypeId) {
      await client.query(
        `
          INSERT INTO app.financial_movements (
            movement_type_id,
            concept,
            amount,
            reference_table,
            reference_id,
            created_by
          )
          VALUES ($1, $2, $3, $4, $5, $6)
        `,
        [financialTypeId, `Ingreso por venta ${saleNumber}`, total, 'sales', saleId, sellerId]
      );
    }

    await client.query('COMMIT');
    return saleId;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  findAll,
  findRecent,
  findById,
  findSellableProducts,
  createSale
};
