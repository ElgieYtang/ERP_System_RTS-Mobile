const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 8000;

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Matches Flutter's ApiSettings.builtinDefault (http://<host>:8000/api/mobile/...)
app.use('/api/mobile', require('./routes'));

const db = require('./config/db');
const { assertDatabaseSchema } = require('./config/schema');
const { startDiscoveryServer } = require('./discovery');

async function start() {
  await assertDatabaseSchema(db);
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Node.js ERP server running at http://0.0.0.0:${PORT}/api/mobile`);
    if (typeof startDiscoveryServer === 'function') {
      startDiscoveryServer(PORT);
    }
  });
}

start().catch((err) => {
  console.error('Failed to start server:', err.message);
  process.exit(1);
});