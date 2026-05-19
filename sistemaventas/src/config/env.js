const dotenv = require('dotenv');

dotenv.config();

function parseBoolean(value, fallback = false) {
  if (value == null || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

const env = {
  appName: process.env.APP_NAME || 'Sistema Ventas',
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  databaseUrl: process.env.DATABASE_URL || '',
  sessionSecret: process.env.SESSION_SECRET || 'cambia-esta-clave-en-produccion',
  redisUrl: process.env.REDIS_URL || '',
  sessionPrefix: process.env.SESSION_PREFIX || 'sistemaventas:sess:',
  forceSecureCookies: parseBoolean(process.env.FORCE_SECURE_COOKIES, false),
  trustProxy: parseBoolean(process.env.TRUST_PROXY, true)
};

module.exports = env;
