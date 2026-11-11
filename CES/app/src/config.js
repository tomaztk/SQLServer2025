// All configuration comes from environment variables (App Service app settings in Azure,
// a .env-style export locally). See ../.env.sample.
const env = process.env;

export const config = {
  port: Number(env.PORT || 8080),
  // live  = consume from Azure Event Hubs (default when EVENTHUB_FQDN is set)
  // mock  = no Azure at all; synthetic CES events are generated in-process (UI preview)
  mode: (env.DEMO_MODE || (env.EVENTHUB_FQDN ? 'live' : 'mock')).toLowerCase(),
  eventHubFqdn: env.EVENTHUB_FQDN,
  eventHubName: env.EVENTHUB_NAME || 'sql-changes',
  consumerGroup: env.EVENTHUB_CONSUMER_GROUP || '$Default',
  startPosition: (env.EVENTHUB_START_POSITION || 'latest').toLowerCase(), // latest | earliest
  checkpointBlobEndpoint: env.CHECKPOINT_BLOB_ENDPOINT || '',
  checkpointContainer: env.CHECKPOINT_CONTAINER || 'checkpoints',
  streamGroup: env.CES_STREAM_GROUP || 'CesDemoGroup',
  sql: {
    server: env.SQL_SERVER || '',
    port: Number(env.SQL_PORT || 1433),
    database: env.SQL_DATABASE || 'CesDemo',
    user: env.SQL_USER || '',
    password: env.SQL_PASSWORD || '',
    trustServerCertificate: (env.SQL_TRUST_SERVER_CERTIFICATE || 'true') === 'true',
  },
  simulatorAutostart: env.SIMULATOR_AUTOSTART === 'true',
  // When set, every POST (simulator / synthetic) needs header "x-admin-token".
  adminToken: env.ADMIN_TOKEN || '',
};
