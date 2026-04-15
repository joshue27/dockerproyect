const path = require('path');
const express = require('express');
const session = require('express-session');
const { RedisStore } = require('connect-redis');
const webRoutes = require('./routes/web');
const env = require('./config/env');
const { getRedisClient } = require('./config/redis');

const app = express();
const redisClient = getRedisClient(env.redisUrl);
const sessionConfig = {
  secret: env.sessionSecret,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: false,
    maxAge: 1000 * 60 * 60 * 8
  }
};

if (redisClient) {
  sessionConfig.store = new RedisStore({
    client: redisClient,
    prefix: env.sessionPrefix
  });
}

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

app.use(session(sessionConfig));

app.use((req, res, next) => {
  res.locals.currentPath = req.path;
  res.locals.currentUser = req.session.user || null;
  next();
});

app.use('/', webRoutes);

app.use((req, res) => {
  res.status(404).render('error', {
    title: 'No encontrado',
    message: 'La ruta solicitada no existe.'
  });
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).render('error', {
    title: 'Error interno',
    message: 'Ocurrio un error inesperado en la aplicacion.'
  });
});

module.exports = app;
