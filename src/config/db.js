const sql = require('mssql');

let pool;

const config = {
  server: process.env.DB_SERVER || '137.184.49.80',
  database: process.env.DB_NAME || 'DRUSH',
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || 'Hranaaram789',
  port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 1433,
  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate: true
  }
};

async function getPool() {
  if (pool) {
    return pool;
  }

  pool = await new sql.ConnectionPool(config).connect();
  return pool;
}

module.exports = {
  sql,
  getPool
};
