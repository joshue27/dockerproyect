const usersRepository = require('../repositories/usersRepository');

function buildFormData(body = {}) {
  return {
    username: body.username || '',
    fullName: body.fullName || '',
    email: body.email || '',
    roleId: body.roleId || '',
    password: body.password || '',
    isActive: body.isActive === 'on'
  };
}

function mapUserToForm(user) {
  return {
    username: user.username,
    fullName: user.full_name,
    email: user.email || '',
    roleId: String(user.role_id),
    password: '',
    isActive: user.is_active
  };
}

function validateUser(formData, { requirePassword = true } = {}) {
  const errors = [];

  if (!formData.username.trim()) {
    errors.push('El nombre de usuario es obligatorio.');
  }

  if (!formData.fullName.trim()) {
    errors.push('El nombre completo es obligatorio.');
  }

  if (!formData.roleId) {
    errors.push('Debés seleccionar un rol.');
  }

  if (formData.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
    errors.push('El correo electrónico no tiene un formato válido.');
  }

  if (requirePassword && !formData.password.trim()) {
    errors.push('La contraseña es obligatoria.');
  }

  return errors;
}

async function index(req, res, next) {
  try {
    const users = await usersRepository.findAll();
    const feedbackMessages = {
      created: 'Usuario creado correctamente.',
      updated: 'Usuario actualizado correctamente.',
      toggled: 'Estado del usuario actualizado correctamente.'
    };

    return res.render('users/index', {
      title: 'Usuarios',
      users,
      message: feedbackMessages[req.query.status] || null,
      currentUserId: req.session.user.id
    });
  } catch (error) {
    return next(error);
  }
}

async function createView(req, res, next) {
  try {
    const roles = await usersRepository.findRoles();

    return res.render('users/form', {
      title: 'Nuevo usuario',
      formTitle: 'Crear usuario',
      formAction: '/usuarios',
      submitLabel: 'Guardar usuario',
      errors: [],
      roles,
      helpText: 'Creá cuentas básicas para administración, ventas o bodega.',
      user: {
        ...buildFormData({}),
        isActive: true
      },
      isEdit: false
    });
  } catch (error) {
    return next(error);
  }
}

async function store(req, res, next) {
  const formData = buildFormData(req.body);
  const errors = validateUser(formData, { requirePassword: true });

  if (errors.length > 0) {
    try {
      const roles = await usersRepository.findRoles();
      return res.status(422).render('users/form', {
        title: 'Nuevo usuario',
        formTitle: 'Crear usuario',
        formAction: '/usuarios',
        submitLabel: 'Guardar usuario',
        errors,
        roles,
        helpText: 'Creá cuentas básicas para administración, ventas o bodega.',
        user: formData,
        isEdit: false
      });
    } catch (renderError) {
      return next(renderError);
    }
  }

  try {
    await usersRepository.create({
      username: formData.username.trim(),
      fullName: formData.fullName.trim(),
      email: formData.email.trim(),
      roleId: Number(formData.roleId),
      password: formData.password,
      isActive: formData.isActive
    });

    return res.redirect('/usuarios?status=created');
  } catch (error) {
    if (error.code === '23505') {
      try {
        const roles = await usersRepository.findRoles();
        return res.status(409).render('users/form', {
          title: 'Nuevo usuario',
          formTitle: 'Crear usuario',
          formAction: '/usuarios',
          submitLabel: 'Guardar usuario',
          errors: ['El usuario o correo ya existe.'],
          roles,
          helpText: 'Creá cuentas básicas para administración, ventas o bodega.',
          user: {
            ...formData,
            password: ''
          },
          isEdit: false
        });
      } catch (renderError) {
        return next(renderError);
      }
    }

    return next(error);
  }
}

async function editView(req, res, next) {
  try {
    const [user, roles] = await Promise.all([
      usersRepository.findById(req.params.id),
      usersRepository.findRoles()
    ]);

    if (!user) {
      return res.status(404).render('error', {
        title: 'Usuario no encontrado',
        message: 'No existe el usuario que intentás editar.'
      });
    }

    return res.render('users/form', {
      title: 'Editar usuario',
      formTitle: 'Editar usuario',
      formAction: `/usuarios/${user.id}/editar`,
      submitLabel: 'Actualizar usuario',
      errors: [],
      roles,
      helpText: 'Podés actualizar datos básicos, rol y estado del usuario.',
      user: mapUserToForm(user),
      isEdit: true
    });
  } catch (error) {
    return next(error);
  }
}

async function update(req, res, next) {
  const userId = Number(req.params.id);
  const formData = buildFormData(req.body);
  const errors = validateUser(formData, { requirePassword: false });

  if (userId === req.session.user.id && !formData.isActive) {
    errors.push('No podés desactivar tu propio usuario desde esta sesión.');
  }

  if (errors.length > 0) {
    try {
      const roles = await usersRepository.findRoles();
      return res.status(422).render('users/form', {
        title: 'Editar usuario',
        formTitle: 'Editar usuario',
        formAction: `/usuarios/${userId}/editar`,
        submitLabel: 'Actualizar usuario',
        errors,
        roles,
        helpText: 'Podés actualizar datos básicos, rol y estado del usuario.',
        user: {
          ...formData,
          password: ''
        },
        isEdit: true
      });
    } catch (renderError) {
      return next(renderError);
    }
  }

  try {
    const updatedUser = await usersRepository.update(userId, {
      username: formData.username.trim(),
      fullName: formData.fullName.trim(),
      email: formData.email.trim(),
      roleId: Number(formData.roleId),
      password: formData.password.trim(),
      isActive: formData.isActive
    });

    if (!updatedUser) {
      return res.status(404).render('error', {
        title: 'Usuario no encontrado',
        message: 'No existe el usuario que intentás actualizar.'
      });
    }

    if (updatedUser.id === req.session.user.id) {
      const roles = await usersRepository.findRoles();
      const currentRole = roles.find((role) => role.id === updatedUser.role_id);

      req.session.user = {
        ...req.session.user,
        username: updatedUser.username,
        fullName: updatedUser.full_name,
        email: updatedUser.email,
        roleName: currentRole ? currentRole.name : req.session.user.roleName
      };
    }

    return res.redirect('/usuarios?status=updated');
  } catch (error) {
    if (error.code === '23505') {
      try {
        const roles = await usersRepository.findRoles();
        return res.status(409).render('users/form', {
          title: 'Editar usuario',
          formTitle: 'Editar usuario',
          formAction: `/usuarios/${userId}/editar`,
          submitLabel: 'Actualizar usuario',
          errors: ['El usuario o correo ya existe.'],
          roles,
          helpText: 'Podés actualizar datos básicos, rol y estado del usuario.',
          user: {
            ...formData,
            password: ''
          },
          isEdit: true
        });
      } catch (renderError) {
        return next(renderError);
      }
    }

    return next(error);
  }
}

async function toggleActive(req, res, next) {
  const userId = Number(req.params.id);

  if (userId === req.session.user.id) {
    return res.status(409).render('error', {
      title: 'Acción no permitida',
      message: 'No podés desactivar tu propio usuario desde esta pantalla.'
    });
  }

  try {
    const user = await usersRepository.toggleActive(userId);

    if (!user) {
      return res.status(404).render('error', {
        title: 'Usuario no encontrado',
        message: 'No existe el usuario que intentás actualizar.'
      });
    }

    return res.redirect('/usuarios?status=toggled');
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  index,
  createView,
  store,
  editView,
  update,
  toggleActive
};
