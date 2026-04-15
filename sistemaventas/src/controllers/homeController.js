const dashboardRepository = require('../repositories/dashboardRepository');
const env = require('../config/env');

async function index(req, res) {
  let stats = {
    totalProducts: 0,
    lowStockProducts: 0,
    totalSales: 0,
    pendingRequests: 0,
    recentSales: []
  };

  let databaseConnected = true;
  let databaseMessage = 'Base de datos conectada correctamente.';

  try {
    stats = await dashboardRepository.findDashboardStats();
  } catch (error) {
    databaseConnected = false;
    databaseMessage = 'La app arranco, pero la base de datos aun no responde. Esto es normal mientras no levantemos PostgreSQL.';
  }

  res.render('home', {
    title: 'Dashboard',
    appName: env.appName,
    stats,
    databaseConnected,
    databaseMessage
  });
}

function health(req, res) {
  res.status(200).json({
    status: 'ok',
    service: 'sistemaventas-web'
  });
}

module.exports = {
  index,
  health
};
