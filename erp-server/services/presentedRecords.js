const db = require('../config/db');
const { TABLES, billingPaymentStatus } = require('../config/schema');
const tp = require('./transactionPresenter');
const { enrichOutslipDetailLines, enrichDeliveryDetailLines } = require('./outslipLines');

async function setupItemsMap(itemIds) {
  const ids = [...new Set(itemIds.filter(Boolean))];
  if (ids.length === 0) return new Map();
  const [rows] = await db.query('SELECT id, item_name, barcode FROM setup_items WHERE id IN (?)', [ids]);
  return new Map(rows.map((r) => [r.id, r]));
}

async function loadOutslip(id) {
  const [[os]] = await db.query(
    `SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`,
    [id, id]
  );
  if (!os) return null;
  const [details] = await db.query(`SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`, [os.id]);
  const lines = await enrichOutslipDetailLines(os, details);
  const [[receivingRow]] = await db.query(
    `SELECT id, receiving_no FROM ${TABLES.RECEIVING_MAIN} WHERE id = ?`,
    [os.receiving_id]
  );
  const [gpRows] = await db.query(`SELECT * FROM ${TABLES.GATE_PASS} WHERE outslip_id = ?`, [os.id]);
  return tp.outslip(os, lines, gpRows[0], receivingRow);
}

async function loadQuotation(id) {
  const [[q]] = await db.query(
    `SELECT * FROM ${TABLES.QUOTATION_MAIN} WHERE id = ? OR quotation_no = ?`,
    [id, id]
  );
  if (!q) return null;
  const [details] = await db.query(`SELECT * FROM ${TABLES.QUOTATION_DETAILS} WHERE quotation_id = ?`, [q.id]);
  return tp.quotation(q, details);
}

async function loadReceiving(id) {
  const [[joined]] = await db.query(
    `SELECT r.*, po.id AS po_row_id, po.supplier_name, po.supplier_id, po.po_no, po.quotation_id,
            q.customer_id AS quotation_customer_id, q.customer_name AS quotation_customer_name
     FROM ${TABLES.RECEIVING_MAIN} r
     LEFT JOIN ${TABLES.PO_MAIN} po ON r.po_id = po.id
     LEFT JOIN ${TABLES.QUOTATION_MAIN} q ON po.quotation_id = q.id
     WHERE r.id = ? OR r.receiving_no = ?`,
    [id, id]
  );
  if (!joined) return null;

  const rcv = { ...joined };
  if (!rcv.customer_id && joined.quotation_customer_id) {
    rcv.customer_id = joined.quotation_customer_id;
    rcv.customer_name = joined.quotation_customer_name;
  }

  const po = joined.po_row_id
    ? {
        id: joined.po_row_id,
        supplier_name: joined.supplier_name,
        supplier_id: joined.supplier_id,
        po_no: joined.po_no,
        quotation_id: joined.quotation_id,
      }
    : null;

  const [details] = await db.query(`SELECT * FROM ${TABLES.RECEIVING_DETAILS} WHERE receiving_id = ?`, [joined.id]);
  const [poDetails] = po
    ? await db.query(`SELECT * FROM ${TABLES.PO_DETAILS} WHERE po_id = ?`, [po.id])
    : [[]];
  const setupItemsById = await setupItemsMap(details.map((d) => d.item_id));
  return tp.receiving(rcv, details, po, poDetails, setupItemsById);
}

async function loadDelivery(id) {
  const [[dr]] = await db.query(
    `SELECT * FROM ${TABLES.DELIVERY_MAIN} WHERE id = ? OR dr_no = ?`,
    [id, id]
  );
  if (!dr) return null;
  const [detailsRaw] = await db.query(
    `SELECT * FROM ${TABLES.DELIVERY_DETAILS} WHERE delivery_id = ?`,
    [dr.id]
  );
  const details = await enrichDeliveryDetailLines(dr, detailsRaw);
  const [[outslip]] = await db.query(`SELECT id, outslip_no FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ?`, [dr.outslip_id]);
  const setupItemsById = await setupItemsMap(details.map((d) => d.item_id));
  return tp.deliveryReceipt(dr, details, outslip, setupItemsById);
}

async function loadPurchaseOrder(id) {
  const [[po]] = await db.query(
    `SELECT * FROM ${TABLES.PO_MAIN} WHERE id = ? OR po_no = ?`,
    [id, id]
  );
  if (!po) return null;
  const [details] = await db.query(`SELECT * FROM ${TABLES.PO_DETAILS} WHERE po_id = ?`, [po.id]);
  let quotationRow = null;
  if (po.quotation_id) {
    const [[q]] = await db.query(
      `SELECT id, quotation_no FROM ${TABLES.QUOTATION_MAIN} WHERE id = ?`,
      [po.quotation_id]
    );
    quotationRow = q;
  }
  return tp.purchaseOrder(po, details, quotationRow);
}

async function loadBilling(id) {
  const [[row]] = await db.query(`SELECT * FROM ${TABLES.BILLING} WHERE id = ? OR billing_no = ?`, [id, id]);
  if (!row) return null;
  const [payments] = await db.query('SELECT * FROM billing_payments WHERE billing_id = ?', [row.id]);
  const [[delivery]] = await db.query(`SELECT id, dr_no FROM ${TABLES.DELIVERY_MAIN} WHERE id = ?`, [row.delivery_id]);
  const presented = tp.billing(row, payments, delivery);
  return { ...presented, paymentStatus: billingPaymentStatus(row) };
}

module.exports = {
  loadOutslip,
  loadQuotation,
  loadPurchaseOrder,
  loadReceiving,
  loadDelivery,
  loadBilling,
};
