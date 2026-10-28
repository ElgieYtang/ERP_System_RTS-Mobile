const db = require('../config/db');
const { TABLES } = require('../config/schema');

async function quantitiesByItemId(branchId = null) {
  let query = `
    SELECT item_id, SUM(\`in\`) AS qty_in, SUM(\`out\`) AS qty_out
    FROM ${TABLES.INVENTORY}
    WHERE item_id > 0
  `;
  const params = [];
  if (branchId) {
    query += ' AND branch_id = ?';
    params.push(branchId);
  }
  query += ' GROUP BY item_id';

  const [rows] = await db.query(query, params);
  const map = new Map();
  for (const row of rows) {
    map.set(row.item_id, parseFloat(row.qty_in || 0) - parseFloat(row.qty_out || 0));
  }
  return map;
}

function statusLabel(quantity) {
  const q = parseFloat(quantity || 0);
  if (q <= 0) return 'Out of Stock';
  if (q <= 5) return 'Low Stock';
  return 'In Stock';
}

module.exports = { quantitiesByItemId, statusLabel };
