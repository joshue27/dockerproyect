function requireAuth(req, res, next) {
  if (!req.session.user) {
    return res.redirect('/login');
  }

  return next();
}

function requireRole(roleName) {
  return (req, res, next) => {
    if (!req.session.user) {
      return res.redirect('/login');
    }

    if (req.session.user.roleName !== roleName) {
      return res.status(403).render('error', {
        title: 'Acceso denegado',
        message: 'No tenés permisos para acceder a este módulo.'
      });
    }

    return next();
  };
}

module.exports = {
  requireAuth,
  requireRole
};
