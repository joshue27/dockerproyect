const pool = require('../db/pool');

async function findAll() {
  const query = `
    SELECT
      cr.id,
      cr.customer_name,
      cr.contact_phone,
      cr.description,
      cr.created_at,
      cr.updated_at,
      rt.name AS request_type,
      rs.name AS status_name,
      u.full_name AS created_by_name
    FROM app.customer_requests cr
    INNER JOIN app.request_types rt ON rt.id = cr.request_type_id
    INNER JOIN app.request_statuses rs ON rs.id = cr.status_id
    INNER JOIN app.users u ON u.id = cr.created_by
    ORDER BY cr.created_at DESC, cr.id DESC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findById(id) {
  const query = `
    SELECT
      cr.id,
      cr.customer_name,
      cr.contact_phone,
      cr.description,
      cr.created_at,
      cr.updated_at,
      rt.name AS request_type,
      rs.name AS status_name,
      u.full_name AS created_by_name
    FROM app.customer_requests cr
    INNER JOIN app.request_types rt ON rt.id = cr.request_type_id
    INNER JOIN app.request_statuses rs ON rs.id = cr.status_id
    INNER JOIN app.users u ON u.id = cr.created_by
    WHERE cr.id = $1
  `;

  const result = await pool.query(query, [id]);
  return result.rows[0] || null;
}

async function findCatalogs() {
  const [typesResult, statusesResult] = await Promise.all([
    pool.query('SELECT id, name FROM app.request_types ORDER BY name ASC'),
    pool.query('SELECT id, name FROM app.request_statuses ORDER BY id ASC')
  ]);

  return {
    requestTypes: typesResult.rows,
    requestStatuses: statusesResult.rows
  };
}

async function createRequest(request) {
  const creatorResult = await pool.query(
    `SELECT id FROM app.users WHERE username = 'caja01' LIMIT 1`
  );

  if (creatorResult.rows.length === 0) {
    throw new Error('No existe el usuario por defecto para registrar solicitudes (caja01).');
  }

  const createdBy = creatorResult.rows[0].id;

  const query = `
    INSERT INTO app.customer_requests (
      request_type_id,
      status_id,
      customer_name,
      contact_phone,
      description,
      created_by
    )
    VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING id
  `;

  const values = [
    request.requestTypeId,
    request.statusId,
    request.customerName,
    request.contactPhone,
    request.description,
    createdBy
  ];

  const result = await pool.query(query, values);
  return result.rows[0].id;
}

async function updateStatus(id, statusId) {
  const query = `
    UPDATE app.customer_requests
    SET
      status_id = $2,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $1
    RETURNING id
  `;

  const result = await pool.query(query, [id, statusId]);
  return result.rows[0] || null;
}

module.exports = {
  findAll,
  findById,
  findCatalogs,
  createRequest,
  updateStatus
};
