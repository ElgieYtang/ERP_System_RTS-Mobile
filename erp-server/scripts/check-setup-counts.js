require('dotenv').config();
const db = require('../config/db');

async function main() {
  const tables = ['setup_items', 'setup_customer', 'setup_supplier', 'setup_brand'];
  for (const table of tables) {
    const [[row]] = await db.query(`SELECT COUNT(*) AS c FROM \`${table}\``);
    console.log(`${table}: ${row.c}`);
  }
  const [items] = await db.query(
    'SELECT id, item_name, status, barcode FROM setup_items ORDER BY id LIMIT 8'
  );
  console.log('sample items:', items);
  await db.end();
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
