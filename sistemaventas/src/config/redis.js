const { createClient } = require('redis');

let redisClient;
let redisConnectPromise;

function getRedisClient(redisUrl) {
  if (!redisUrl) {
    return null;
  }

  if (!redisClient) {
    redisClient = createClient({
      url: redisUrl
    });

    redisClient.on('error', error => {
      console.error('[redis] error', error);
    });
  }

  return redisClient;
}

async function connectRedis(redisUrl) {
  const client = getRedisClient(redisUrl);

  if (!client) {
    return null;
  }

  if (!redisConnectPromise) {
    redisConnectPromise = client.connect();
  }

  await redisConnectPromise;
  return client;
}

module.exports = {
  getRedisClient,
  connectRedis
};
