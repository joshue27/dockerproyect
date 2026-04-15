const salesRepository = require('../repositories/salesRepository');

function buildFormData(body = {}, products = []) {
  return {
    customerName: body.customerName || '',
    discount: body.discount || '0',
    items: products.map(product => ({
      productId: product.id,
      sku: product.sku,
      name: product.name,
      price: product.price,
      stock: product.stock,
      quantity: body[`quantity_${product.id}`] || '0'
    }))
  };
}

function validateSale(formData) {
  const errors = [];
  const selectedItems = [];
  const discount = Number(formData.discount || 0);

  if (Number.isNaN(discount) || discount < 0) {
    errors.push('El descuento debe ser un numero valido mayor o igual a 0.');
  }

  for (const item of formData.items) {
    const quantity = Number(item.quantity);

    if (item.quantity === '' || quantity === 0) {
      continue;
    }

    if (!Number.isInteger(quantity) || quantity < 0) {
      errors.push(`La cantidad para ${item.name} debe ser un entero valido.`);
      continue;
    }

    if (quantity > item.stock) {
      errors.push(`La cantidad para ${item.name} excede el stock disponible.`);
      continue;
    }

    selectedItems.push({
      productId: item.productId,
      quantity
    });
  }

  if (selectedItems.length === 0) {
    errors.push('Debes seleccionar al menos un producto para la venta.');
  }

  return {
    errors,
    selectedItems,
    discount
  };
}

function buildSummary(formData) {
  const selectedItems = formData.items
    .map(item => {
      const quantity = Number(item.quantity || 0);
      const unitPrice = Number(item.price || 0);
      const subtotal = quantity > 0 ? quantity * unitPrice : 0;

      return {
        ...item,
        quantityNumber: quantity,
        subtotal
      };
    })
    .filter(item => item.quantityNumber > 0);

  const subtotal = selectedItems.reduce((acc, item) => acc + item.subtotal, 0);
  const discount = Number(formData.discount || 0);
  const normalizedDiscount = Number.isNaN(discount) || discount < 0 ? 0 : discount;

  return {
    selectedItems,
    subtotal,
    discount: normalizedDiscount,
    total: Math.max(subtotal - normalizedDiscount, 0)
  };
}

async function index(req, res, next) {
  try {
    const sales = await salesRepository.findAll();
    const feedbackMessages = {
      created: 'Venta registrada correctamente.'
    };

    res.render('sales/index', {
      title: 'Ventas',
      sales,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    next(error);
  }
}

async function createView(req, res, next) {
  try {
    const products = await salesRepository.findSellableProducts();
    const formData = buildFormData({}, products);

    res.render('sales/form', {
      title: 'Nueva venta',
      errors: [],
      formData,
      summary: buildSummary(formData)
    });
  } catch (error) {
    next(error);
  }
}

async function store(req, res, next) {
  try {
    const products = await salesRepository.findSellableProducts();
    const formData = buildFormData(req.body, products);
    const { errors, selectedItems, discount } = validateSale(formData);

    if (errors.length > 0) {
      return res.status(422).render('sales/form', {
        title: 'Nueva venta',
        errors,
        formData,
        summary: buildSummary(formData)
      });
    }

    const saleId = await salesRepository.createSale({
      customerName: formData.customerName.trim() || null,
      discount,
      items: selectedItems
    });

    return res.redirect(`/ventas/${saleId}?status=created`);
  } catch (error) {
    if (error.message) {
      try {
        const products = await salesRepository.findSellableProducts();
        const formData = buildFormData(req.body, products);

        return res.status(422).render('sales/form', {
          title: 'Nueva venta',
          errors: [error.message],
          formData,
          summary: buildSummary(formData)
        });
      } catch (renderError) {
        return next(renderError);
      }
    }

    return next(error);
  }
}

async function show(req, res, next) {
  try {
    const sale = await salesRepository.findById(req.params.id);

    if (!sale) {
      return res.status(404).render('error', {
        title: 'Venta no encontrada',
        message: 'No existe la venta que intentas consultar.'
      });
    }

    const feedbackMessages = {
      created: 'Venta registrada correctamente.'
    };

    return res.render('sales/show', {
      title: 'Detalle de venta',
      sale,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  index,
  createView,
  store,
  show
};
