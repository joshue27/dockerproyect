const pool = require('../db/pool');

async function findByCredentials(username, password) {
  const query = `
    SELECT
      u.id,
      u.username,
      u.full_name,
      u.email,
      u.password_hash,
      r.name AS role_name
    FROM app.users u
    INNER JOIN app.roles r ON r.id = u.role_id
    WHERE u.username = $1
      AND u.is_active = TRUE
    LIMIT 1
  `;

  const result = await pool.query(query, [username]);
  const user = result.rows[0] || null;

  if (!user) {
    return null;
  }

  if (user.password_hash !== password) {
    return null;
  }

  return {
    id: user.id,
    username: user.username,
    fullName: user.full_name,
    email: user.email,
    roleName: user.role_name
  };
}

module.exports = {
  findByCredentials
};
