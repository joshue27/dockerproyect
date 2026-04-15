const express = require('express');
const authController = require('../controllers/authController');
const homeController = require('../controllers/homeController');
const productsController = require('../controllers/productsController');
const salesController = require('../controllers/salesController');
const customerRequestsController = require('../controllers/customerRequestsController');
const financeController = require('../controllers/financeController');
const usersController = require('../controllers/usersController');
const { requireAuth, requireRole } = require('../middleware/authMiddleware');

const router = express.Router();

router.get('/login', authController.loginView);
router.post('/login', authController.login);
router.get('/health', homeController.health);

router.use(requireAuth);

router.post('/logout', authController.logout);
router.get('/', homeController.index);

router.get('/productos', productsController.index);
router.get('/productos/nuevo', productsController.createView);
router.post('/productos', productsController.store);
router.get('/productos/:id', productsController.show);
router.get('/productos/:id/editar', productsController.editView);
router.post('/productos/:id/editar', productsController.update);
router.post('/productos/:id/toggle-active', productsController.toggleActive);

router.get('/ventas', salesController.index);
router.get('/ventas/nueva', salesController.createView);
router.post('/ventas', salesController.store);
router.get('/ventas/:id', salesController.show);

router.get('/solicitudes', customerRequestsController.index);
router.get('/solicitudes/nueva', customerRequestsController.createView);
router.post('/solicitudes', customerRequestsController.store);
router.get('/solicitudes/:id', customerRequestsController.show);
router.post('/solicitudes/:id/estado', customerRequestsController.updateStatus);

router.get('/finanzas', financeController.index);
router.get('/finanzas/egresos/nuevo', financeController.createExpenseView);
router.post('/finanzas/egresos', financeController.storeExpense);

router.get('/usuarios', requireRole('admin'), usersController.index);
router.get('/usuarios/nuevo', requireRole('admin'), usersController.createView);
router.post('/usuarios', requireRole('admin'), usersController.store);
router.get('/usuarios/:id/editar', requireRole('admin'), usersController.editView);
router.post('/usuarios/:id/editar', requireRole('admin'), usersController.update);
router.post('/usuarios/:id/toggle-active', requireRole('admin'), usersController.toggleActive);

module.exports = router;
