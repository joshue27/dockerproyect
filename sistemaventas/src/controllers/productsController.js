const productRepository = require('../repositories/productRepository');

function buildFormData(body = {}) {
  return {
    sku: body.sku || '',
    name: body.name || '',
    description: body.description || '',
    price: body.price || '',
    stock: body.stock || '',
    minStock: body.minStock || '',
    active: body.active === 'on'
  };
}

function validateProduct(formData) {
  const errors = [];

  if (!formData.sku.trim()) {
    errors.push('El SKU es obligatorio.');
  }

  if (!formData.name.trim()) {
    errors.push('El nombre es obligatorio.');
  }

  if (formData.price === '' || Number.isNaN(Number(formData.price)) || Number(formData.price) < 0) {
    errors.push('El precio debe ser un numero valido mayor o igual a 0.');
  }

  if (!Number.isInteger(Number(formData.stock)) || Number(formData.stock) < 0) {
    errors.push('El stock debe ser un numero entero mayor o igual a 0.');
  }

  if (!Number.isInteger(Number(formData.minStock)) || Number(formData.minStock) < 0) {
    errors.push('El stock minimo debe ser un numero entero mayor o igual a 0.');
  }

  return errors;
}

function mapProductToForm(product) {
  return {
    sku: product.sku,
    name: product.name,
    description: product.description || '',
    price: product.price,
    stock: product.stock,
    minStock: product.min_stock,
    active: product.active
  };
}

async function index(req, res, next) {
  try {
    const filter = req.query.filter === 'low-stock' ? 'low-stock' : 'all';
    const products = filter === 'low-stock'
      ? await productRepository.findLowStock()
      : await productRepository.findAll();

    const feedbackMessages = {
      created: 'Producto creado correctamente.',
      updated: 'Producto actualizado correctamente.',
      toggled: 'Estado del producto actualizado correctamente.'
    };

    res.render('products/index', {
      title: 'Productos',
      products,
      filter,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    next(error);
  }
}

function createView(req, res) {
  res.render('products/form', {
    title: 'Nuevo producto',
    formTitle: 'Crear producto',
    formAction: '/productos',
    submitLabel: 'Guardar producto',
    errors: [],
    product: buildFormData()
  });
}

async function store(req, res, next) {
  const formData = buildFormData(req.body);
  const errors = validateProduct(formData);

  if (errors.length > 0) {
    return res.status(422).render('products/form', {
      title: 'Nuevo producto',
      formTitle: 'Crear producto',
      formAction: '/productos',
      submitLabel: 'Guardar producto',
      errors,
      product: formData
    });
  }

  try {
    await productRepository.create({
      sku: formData.sku.trim(),
      name: formData.name.trim(),
      description: formData.description.trim(),
      price: Number(formData.price),
      stock: Number(formData.stock),
      minStock: Number(formData.minStock),
      active: formData.active
    });

    return res.redirect('/productos?status=created');
  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).render('products/form', {
        title: 'Nuevo producto',
        formTitle: 'Crear producto',
        formAction: '/productos',
        submitLabel: 'Guardar producto',
        errors: ['Ya existe un producto con ese SKU.'],
        product: formData
      });
    }

    return next(error);
  }
}

async function show(req, res, next) {
  try {
    const product = await productRepository.findById(req.params.id);

    if (!product) {
      return res.status(404).render('error', {
        title: 'Producto no encontrado',
        message: 'No existe el producto que intentas consultar.'
      });
    }

    return res.render('products/show', {
      title: 'Detalle de producto',
      product
    });
  } catch (error) {
    return next(error);
  }
}

async function editView(req, res, next) {
  try {
    const product = await productRepository.findById(req.params.id);

    if (!product) {
      return res.status(404).render('error', {
        title: 'Producto no encontrado',
        message: 'No existe el producto que intentas editar.'
      });
    }

    return res.render('products/form', {
      title: 'Editar producto',
      formTitle: 'Editar producto',
      formAction: `/productos/${product.id}/editar`,
      submitLabel: 'Actualizar producto',
      errors: [],
      product: mapProductToForm(product)
    });
  } catch (error) {
    return next(error);
  }
}

async function update(req, res, next) {
  const formData = buildFormData(req.body);
  const errors = validateProduct(formData);
  const productId = req.params.id;

  if (errors.length > 0) {
    return res.status(422).render('products/form', {
      title: 'Editar producto',
      formTitle: 'Editar producto',
      formAction: `/productos/${productId}/editar`,
      submitLabel: 'Actualizar producto',
      errors,
      product: formData
    });
  }

  try {
    const updatedProduct = await productRepository.update(productId, {
      sku: formData.sku.trim(),
      name: formData.name.trim(),
      description: formData.description.trim(),
      price: Number(formData.price),
      stock: Number(formData.stock),
      minStock: Number(formData.minStock),
      active: formData.active
    });

    if (!updatedProduct) {
      return res.status(404).render('error', {
        title: 'Producto no encontrado',
        message: 'No existe el producto que intentas actualizar.'
      });
    }

    return res.redirect('/productos?status=updated');
  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).render('products/form', {
        title: 'Editar producto',
        formTitle: 'Editar producto',
        formAction: `/productos/${productId}/editar`,
        submitLabel: 'Actualizar producto',
        errors: ['Ya existe un producto con ese SKU.'],
        product: formData
      });
    }

    return next(error);
  }
}

async function toggleActive(req, res, next) {
  try {
    const product = await productRepository.toggleActive(req.params.id);

    if (!product) {
      return res.status(404).render('error', {
        title: 'Producto no encontrado',
        message: 'No existe el producto que intentas actualizar.'
      });
    }

    return res.redirect('/productos?status=toggled');
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  index,
  createView,
  store,
  show,
  editView,
  update,
  toggleActive
};
