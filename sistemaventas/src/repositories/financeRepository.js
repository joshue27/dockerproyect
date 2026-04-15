const pool = require('../db/pool');

async function findAll() {
  const query = `
    SELECT
      fm.id,
      fmt.name AS movement_type,
      fm.concept,
      fm.amount,
      fm.reference_table,
      fm.reference_id,
      fm.created_at,
      u.full_name AS created_by_name
    FROM app.financial_movements fm
    INNER JOIN app.financial_movement_types fmt ON fmt.id = fm.movement_type_id
    INNER JOIN app.users u ON u.id = fm.created_by
    ORDER BY fm.created_at DESC, fm.id DESC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findSummary() {
  const query = `
    SELECT
      COALESCE(SUM(CASE WHEN fmt.name = 'income' THEN fm.amount ELSE 0 END), 0)::numeric(12,2) AS total_income,
      COALESCE(SUM(CASE WHEN fmt.name = 'expense' THEN fm.amount ELSE 0 END), 0)::numeric(12,2) AS total_expense,
      COALESCE(SUM(CASE WHEN fmt.name = 'income' THEN fm.amount ELSE -fm.amount END), 0)::numeric(12,2) AS balance
    FROM app.financial_movements fm
    INNER JOIN app.financial_movement_types fmt ON fmt.id = fm.movement_type_id
  `;

  const result = await pool.query(query);
  return result.rows[0];
}

async function createExpense({ concept, amount }) {
  const [expenseTypeResult, userResult] = await Promise.all([
    pool.query(`SELECT id FROM app.financial_movement_types WHERE name = 'expense' LIMIT 1`),
    pool.query(`SELECT id FROM app.users WHERE username = 'admin' LIMIT 1`)
  ]);

  if (expenseTypeResult.rows.length === 0) {
    throw new Error('No existe el tipo financiero expense en la base de datos.');
  }

  if (userResult.rows.length === 0) {
    throw new Error('No existe el usuario admin para registrar egresos.');
  }

  const expenseTypeId = expenseTypeResult.rows[0].id;
  const createdBy = userResult.rows[0].id;

  const query = `
    INSERT INTO app.financial_movements (
      movement_type_id,
      concept,
      amount,
      reference_table,
      reference_id,
      created_by
    )
    VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING id
  `;

  const result = await pool.query(query, [expenseTypeId, concept, amount, null, null, createdBy]);
  return result.rows[0].id;
}

module.exports = {
  findAll,
  findSummary,
  createExpense
};
