const db = require('../config/db');

exports.show = async (req, res) => {
  let database = 'ok';
  try {
    await db.query('SELECT 1');
  } catch {
    database = 'error';
  }

  return res.json({
    status: database === 'ok' ? 'ok' : 'degraded',
    app: 'ResponsivCode ERP',
    version: '0.2.0',
    phase: 8,
    database,
  });
};