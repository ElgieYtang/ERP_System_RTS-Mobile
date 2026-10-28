require('dotenv').config();
const mysql = require('mysql2/promise');

const config = {
  port: process.env.PORT || 8000,
  db: {
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'erp_system',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
  },
};

// Create the MySQL connection pool
const pool = mysql.createPool(config.db);

module.exports = pool;
module.exports.config = config;