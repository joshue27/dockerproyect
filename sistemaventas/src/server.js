const app = require('./app');
const env = require('./config/env');
const { connectRedis } = require('./config/redis');

async function bootstrap() {
  await connectRedis(env.redisUrl);

  app.listen(env.port, () => {
    console.log(`[boot] ${env.appName} escuchando en puerto ${env.port}`);
  });
}

bootstrap().catch(error => {
  console.error('[boot] error fatal', error);
  process.exit(1);
});
