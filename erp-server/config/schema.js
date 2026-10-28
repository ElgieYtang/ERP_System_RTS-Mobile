/**
 * Canonical MySQL table names (Laravel / WAMP schema).
 * Import { TABLES } in controllers — do not hard-code legacy names like po_main.
 *
 * Legacy name (wrong)     → TABLES constant        → Real table
 * po_main                 → TABLES.PO_MAIN         → purchase_main
 * po_details              → TABLES.PO_DETAILS      → purchase_details
 * billing_main            → TABLES.BILLING         → billing
 * gate_pass               → TABLES.GATE_PASS       → gate_pass_main
 * inventory_movement      → TABLES.INVENTORY       → inventory
 * ar_contract_lines       → TABLES.AR_CONTRACT_LINES → ar_recurring_lines
 */
const LEGACY_TABLE_NAMES = Object.freeze([
  'po_main',
  'po_details',
  'billing_main',
  'gate_pass',
  'inventory_movement',
  'ar_contract_lines',
  'app_settings',
]);

const TABLES = Object.freeze({
  PO_MAIN: 'purchase_main',
  PO_DETAILS: 'purchase_details',
  BILLING: 'billing',
  GATE_PASS: 'gate_pass_main',
  INVENTORY: 'inventory',
  AR_CONTRACT_LINES: 'ar_recurring_lines',
  SETTINGS: 'settings',
  QUOTATION_MAIN: 'quotation_main',
  QUOTATION_DETAILS: 'quotation_details',
  RECEIVING_MAIN: 'receiving_main',
  RECEIVING_DETAILS: 'receiving_details',
  OUTSLIP_MAIN: 'outslip_main',
  OUTSLIP_DETAILS: 'outslip_details',
  DELIVERY_MAIN: 'delivery_main',
  DELIVERY_DETAILS: 'delivery_details',
  SETUP_USERS: 'setup_users',
  API_TOKENS: 'api_tokens',
});

/** Tables the mobile API must have at startup. */
const REQUIRED_TABLES = [
  TABLES.PO_MAIN,
  TABLES.PO_DETAILS,
  TABLES.BILLING,
  TABLES.QUOTATION_MAIN,
  TABLES.QUOTATION_DETAILS,
  TABLES.RECEIVING_MAIN,
  TABLES.SETUP_USERS,
  TABLES.API_TOKENS,
];

function billingPaymentStatus(row) {
  const total = parseFloat(row.billing_total || 0);
  const paid = parseFloat(row.paid_amount || 0);
  if (paid <= 0) return 'unpaid';
  if (paid >= total && total > 0) return 'paid';
  if (paid > 0) return 'partially_paid';
  return (row.status || 'unpaid').toString().toLowerCase();
}

async function assertDatabaseSchema(pool) {
  const [rows] = await pool.query(
    `SELECT TABLE_NAME AS name
     FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (?)`,
    [REQUIRED_TABLES]
  );
  const found = new Set(rows.map((r) => r.name));
  const missing = REQUIRED_TABLES.filter((t) => !found.has(t));
  if (missing.length > 0) {
    const msg = `Database schema mismatch. Missing tables: ${missing.join(', ')}`;
    console.error(msg);
    throw new Error(msg);
  }
  console.log('Database schema check OK (' + REQUIRED_TABLES.length + ' core tables).');
}

module.exports = {
  TABLES,
  REQUIRED_TABLES,
  LEGACY_TABLE_NAMES,
  billingPaymentStatus,
  assertDatabaseSchema,
};
