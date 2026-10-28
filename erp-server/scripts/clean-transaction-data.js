/**
 * Clears mobile **TRANSACTIONS** module data only (sidebar: Quotations → Billing).
 * Keeps: setup_users, api_tokens (stay logged in), accomplishments, AR contracts, SOA master data.
 *
 * Command Prompt:
 *   set CONFIRM_CLEAN=yes
 *   npm run clean-transactions
 *
 * PowerShell:
 *   $env:CONFIRM_CLEAN="yes"; npm run clean-transactions
 */
require('dotenv').config();
const db = require('../config/db');
const { TABLES } = require('../config/schema');

/** Delete order respects typical FK chains (child tables first). */
const TRANSACTION_TABLES = [
  'billing_payments',
  TABLES.BILLING,
  TABLES.DELIVERY_DETAILS,
  TABLES.DELIVERY_MAIN,
  TABLES.GATE_PASS,
  TABLES.OUTSLIP_DETAILS,
  TABLES.OUTSLIP_MAIN,
  TABLES.RECEIVING_DETAILS,
  TABLES.RECEIVING_MAIN,
  TABLES.PO_DETAILS,
  TABLES.PO_MAIN,
  TABLES.QUOTATION_DETAILS,
  TABLES.QUOTATION_MAIN,
  TABLES.INVENTORY,
];

async function main() {
  if (process.env.CONFIRM_CLEAN !== 'yes') {
    console.error(
      'Refusing to run without confirmation.\n\n' +
        'Command Prompt:\n' +
        '  set CONFIRM_CLEAN=yes\n' +
        '  npm run clean-transactions\n\n' +
        'PowerShell:\n' +
        '  $env:CONFIRM_CLEAN="yes"; npm run clean-transactions'
    );
    process.exit(1);
  }

  const conn = await db.getConnection();
  try {
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');

    for (const table of TRANSACTION_TABLES) {
      await conn.query(`DELETE FROM \`${table}\``);
      console.log(`Cleared ${table}`);
    }

    // Ledger entries created by PO / billing (not accomplishments or AR contracts).
    await conn.query('DELETE FROM supplier_ledger');
    console.log('Cleared supplier_ledger');
    await conn.query('DELETE FROM customer_ledger');
    console.log('Cleared customer_ledger');

    await conn.query('SET FOREIGN_KEY_CHECKS = 1');
    console.log(
      '\nDone. Transaction pages should be empty. Login, accomplishments, and setup were not removed.'
    );
  } finally {
    conn.release();
    await db.end();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
