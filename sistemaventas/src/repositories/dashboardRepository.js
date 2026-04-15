const pool = require('../db/pool');
const salesRepository = require('./salesRepository');

async function findDashboardStats() {
  const [productsResult, lowStockResult, salesResult, requestsResult, recentSales] = await Promise.all([
    pool.query('SELECT COUNT(*)::int AS total FROM app.products WHERE active = TRUE'),
    pool.query('SELECT COUNT(*)::int AS total FROM app.products WHERE stock <= min_stock AND active = TRUE'),
    pool.query('SELECT COUNT(*)::int AS total FROM app.sales'),
    pool.query(`
      SELECT COUNT(*)::int AS total
      FROM app.customer_requests cr
      INNER JOIN app.request_statuses rs ON rs.id = cr.status_id
      WHERE rs.name = 'pendiente'
    `),
    salesRepository.findRecent(5)
  ]);

  return {
    totalProducts: productsResult.rows[0].total,
    lowStockProducts: lowStockResult.rows[0].total,
    totalSales: salesResult.rows[0].total,
    pendingRequests: requestsResult.rows[0].total,
    recentSales
  };
}

module.exports = {
  findDashboardStats
};
