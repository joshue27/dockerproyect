const customerRequestsRepository = require('../repositories/customerRequestsRepository');

function buildFormData(body = {}) {
  return {
    requestTypeId: body.requestTypeId || '',
    statusId: body.statusId || '',
    customerName: body.customerName || '',
    contactPhone: body.contactPhone || '',
    description: body.description || ''
  };
}

function validateRequest(formData) {
  const errors = [];

  if (!formData.requestTypeId) {
    errors.push('El tipo de solicitud es obligatorio.');
  }

  if (!formData.statusId) {
    errors.push('El estado inicial es obligatorio.');
  }

  if (!formData.customerName.trim()) {
    errors.push('El nombre del cliente es obligatorio.');
  }

  if (!formData.description.trim()) {
    errors.push('La descripcion es obligatoria.');
  }

  return errors;
}

async function index(req, res, next) {
  try {
    const requests = await customerRequestsRepository.findAll();
    const feedbackMessages = {
      created: 'Solicitud registrada correctamente.',
      updated: 'Estado de solicitud actualizado correctamente.'
    };

    res.render('customer-requests/index', {
      title: 'Atencion al cliente',
      requests,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    next(error);
  }
}

async function createView(req, res, next) {
  try {
    const catalogs = await customerRequestsRepository.findCatalogs();

    res.render('customer-requests/form', {
      title: 'Nueva solicitud',
      errors: [],
      formData: buildFormData(),
      requestTypes: catalogs.requestTypes,
      requestStatuses: catalogs.requestStatuses
    });
  } catch (error) {
    next(error);
  }
}

async function store(req, res, next) {
  const formData = buildFormData(req.body);
  const errors = validateRequest(formData);

  try {
    const catalogs = await customerRequestsRepository.findCatalogs();

    if (errors.length > 0) {
      return res.status(422).render('customer-requests/form', {
        title: 'Nueva solicitud',
        errors,
        formData,
        requestTypes: catalogs.requestTypes,
        requestStatuses: catalogs.requestStatuses
      });
    }

    const requestId = await customerRequestsRepository.createRequest({
      requestTypeId: Number(formData.requestTypeId),
      statusId: Number(formData.statusId),
      customerName: formData.customerName.trim(),
      contactPhone: formData.contactPhone.trim() || null,
      description: formData.description.trim()
    });

    return res.redirect(`/solicitudes/${requestId}?status=created`);
  } catch (error) {
    if (error.message) {
      try {
        const catalogs = await customerRequestsRepository.findCatalogs();
        return res.status(422).render('customer-requests/form', {
          title: 'Nueva solicitud',
          errors: [error.message],
          formData,
          requestTypes: catalogs.requestTypes,
          requestStatuses: catalogs.requestStatuses
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
    const [request, catalogs] = await Promise.all([
      customerRequestsRepository.findById(req.params.id),
      customerRequestsRepository.findCatalogs()
    ]);

    if (!request) {
      return res.status(404).render('error', {
        title: 'Solicitud no encontrada',
        message: 'No existe la solicitud que intentas consultar.'
      });
    }

    const feedbackMessages = {
      created: 'Solicitud registrada correctamente.',
      updated: 'Estado de solicitud actualizado correctamente.'
    };

    return res.render('customer-requests/show', {
      title: 'Detalle de solicitud',
      request,
      requestStatuses: catalogs.requestStatuses,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    return next(error);
  }
}

async function updateStatus(req, res, next) {
  try {
    if (!req.body.statusId) {
      return res.status(422).render('error', {
        title: 'Estado invalido',
        message: 'Debes seleccionar un estado valido para actualizar la solicitud.'
      });
    }

    const updated = await customerRequestsRepository.updateStatus(req.params.id, Number(req.body.statusId));

    if (!updated) {
      return res.status(404).render('error', {
        title: 'Solicitud no encontrada',
        message: 'No existe la solicitud que intentas actualizar.'
      });
    }

    return res.redirect(`/solicitudes/${req.params.id}?status=updated`);
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  index,
  createView,
  store,
  show,
  updateStatus
};
