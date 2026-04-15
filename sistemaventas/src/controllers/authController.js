const authRepository = require('../repositories/authRepository');

function loginView(req, res) {
  if (req.session.user) {
    return res.redirect('/');
  }

  return res.render('auth/login', {
    title: 'Iniciar sesion',
    error: null,
    formData: {
      username: '',
      password: ''
    }
  });
}

async function login(req, res, next) {
  const formData = {
    username: req.body.username || '',
    password: req.body.password || ''
  };

  if (!formData.username.trim() || !formData.password.trim()) {
    return res.status(422).render('auth/login', {
      title: 'Iniciar sesion',
      error: 'Usuario y contraseña son obligatorios.',
      formData
    });
  }

  try {
    const user = await authRepository.findByCredentials(formData.username.trim(), formData.password);

    if (!user) {
      return res.status(401).render('auth/login', {
        title: 'Iniciar sesion',
        error: 'Credenciales invalidas. Proba con los usuarios demo.',
        formData: {
          username: formData.username,
          password: ''
        }
      });
    }

    req.session.user = user;
    return res.redirect('/');
  } catch (error) {
    return next(error);
  }
}

function logout(req, res, next) {
  req.session.destroy(error => {
    if (error) {
      return next(error);
    }

    res.clearCookie('connect.sid');
    return res.redirect('/login');
  });
}

module.exports = {
  loginView,
  login,
  logout
};
