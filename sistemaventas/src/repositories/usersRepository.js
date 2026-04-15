const pool = require('../db/pool');

async function findAll() {
  const query = `
    SELECT
      u.id,
      u.username,
      u.full_name,
      u.email,
      u.is_active,
      u.created_at,
      r.id AS role_id,
      r.name AS role_name
    FROM app.users u
    INNER JOIN app.roles r ON r.id = u.role_id
    ORDER BY u.created_at DESC, u.id DESC
  `;

  const result = await pool.query(query);
  return result.rows;
}

async function findById(id) {
  const query = `
    SELECT
      u.id,
      u.username,
      u.full_name,
      u.email,
      u.password_hash,
      u.is_active,
      r.id AS role_id,
      r.name AS role_name
    FROM app.users u
    INNER JOIN app.roles r ON r.id = u.role_id
    WHERE u.id = $1
    LIMIT 1
  `;

  const result = await pool.query(query, [id]);
  return result.rows[0] || null;
}

async function findRoles() {
  const result = await pool.query('SELECT id, name FROM app.roles ORDER BY name ASC');
  return result.rows;
}

async function create(user) {
  const query = `
    INSERT INTO app.users (role_id, username, full_name, email, password_hash, is_active)
    VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING id, username, full_name, email, is_active, role_id
  `;

  const values = [
    user.roleId,
    user.username,
    user.fullName,
    user.email || null,
    user.password,
    user.isActive
  ];

  const result = await pool.query(query, values);
  return result.rows[0];
}

async function update(id, user) {
  if (user.password) {
    const query = `
      UPDATE app.users
      SET role_id = $1,
          username = $2,
          full_name = $3,
          email = $4,
          password_hash = $5,
          is_active = $6
      WHERE id = $7
      RETURNING id, username, full_name, email, is_active, role_id
    `;

    const values = [
      user.roleId,
      user.username,
      user.fullName,
      user.email || null,
      user.password,
      user.isActive,
      id
    ];

    const result = await pool.query(query, values);
    return result.rows[0] || null;
  }

  const query = `
    UPDATE app.users
    SET role_id = $1,
        username = $2,
        full_name = $3,
        email = $4,
        is_active = $5
    WHERE id = $6
    RETURNING id, username, full_name, email, is_active, role_id
  `;

  const values = [
    user.roleId,
    user.username,
    user.fullName,
    user.email || null,
    user.isActive,
    id
  ];

  const result = await pool.query(query, values);
  return result.rows[0] || null;
}

async function toggleActive(id) {
  const query = `
    UPDATE app.users
    SET is_active = NOT is_active
    WHERE id = $1
    RETURNING id, username, is_active
  `;

  const result = await pool.query(query, [id]);
  return result.rows[0] || null;
}

module.exports = {
  findAll,
  findById,
  findRoles,
  create,
  update,
  toggleActive
};
