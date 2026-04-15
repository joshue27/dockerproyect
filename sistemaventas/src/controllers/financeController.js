const financeRepository = require('../repositories/financeRepository');

function buildFormData(body = {}) {
  return {
    concept: body.concept || '',
    amount: body.amount || ''
  };
}

function validateExpense(formData) {
  const errors = [];

  if (!formData.concept.trim()) {
    errors.push('El concepto del egreso es obligatorio.');
  }

  const amount = Number(formData.amount);
  if (formData.amount === '' || Number.isNaN(amount) || amount <= 0) {
    errors.push('El monto del egreso debe ser un numero valido mayor a 0.');
  }

  return errors;
}

async function index(req, res, next) {
  try {
    const [summary, movements] = await Promise.all([
      financeRepository.findSummary(),
      financeRepository.findAll()
    ]);

    const feedbackMessages = {
      created: 'Egreso registrado correctamente.'
    };

    res.render('finance/index', {
      title: 'Finanzas',
      summary,
      movements,
      message: feedbackMessages[req.query.status] || null
    });
  } catch (error) {
    next(error);
  }
}

function createExpenseView(req, res) {
  res.render('finance/form', {
    title: 'Nuevo egreso',
    errors: [],
    formData: buildFormData()
  });
}

async function storeExpense(req, res, next) {
  const formData = buildFormData(req.body);
  const errors = validateExpense(formData);

  if (errors.length > 0) {
    return res.status(422).render('finance/form', {
      title: 'Nuevo egreso',
      errors,
      formData
    });
  }

  try {
    await financeRepository.createExpense({
      concept: formData.concept.trim(),
      amount: Number(formData.amount)
    });

    return res.redirect('/finanzas?status=created');
  } catch (error) {
    if (error.message) {
      return res.status(422).render('finance/form', {
        title: 'Nuevo egreso',
        errors: [error.message],
        formData
      });
    }

    return next(error);
  }
}

module.exports = {
  index,
  createExpenseView,
  storeExpense
};
