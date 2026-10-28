const db = require('../config/db');
const { TABLES } = require('../config/schema');

async function safeCount(query, params = []) {
  try {
    const [rows] = await db.query(query, params);
    return rows[0]?.count || 0;
  } catch {
    return 0;
  }
}

exports.stats = async (req, res) => {
  const [
    pendingQuotations,
    openPurchaseOrders,
    pendingReceiving,
    pendingOutslips,
    activeDeliveries,
    unpaidBills,
    pendingAccomplishments,
  ] = await Promise.all([
    safeCount(
      `SELECT COUNT(*) AS count FROM ${TABLES.QUOTATION_MAIN} WHERE status NOT IN ('CANCELLED', 'INACTIVE', 'APPROVED')`
    ),
    safeCount(
      `SELECT COUNT(*) AS count FROM ${TABLES.PO_MAIN} WHERE status NOT IN ('CANCELLED', 'INACTIVE', 'FULLY_RECEIVED', 'COMPLETED')`
    ),
    safeCount(`SELECT COUNT(*) AS count FROM ${TABLES.RECEIVING_MAIN} WHERE status != 'COMPLETED'`),
    safeCount(
      `SELECT COUNT(*) AS count FROM ${TABLES.OUTSLIP_MAIN} WHERE status IN ('PENDING', 'DRAFT', 'APPROVED')`
    ),
    safeCount(
      `SELECT COUNT(*) AS count FROM ${TABLES.DELIVERY_MAIN} WHERE status IN ('ACTIVE', 'PENDING', 'OUT FOR DELIVERY', 'OUT_FOR_DELIVERY')`
    ),
    safeCount(
      `SELECT COUNT(*) AS count FROM ${TABLES.BILLING} WHERE paid_amount < billing_total OR paid_amount IS NULL OR paid_amount = 0`
    ),
    safeCount("SELECT COUNT(*) AS count FROM accomplishment_main WHERE status = 'PENDING'"),
  ]);

  return res.json({
    data: {
      pendingQuotations,
      openPurchaseOrders,
      pendingReceiving,
      pendingOutslips,
      activeDeliveries,
      unpaidBills,
      pendingAccomplishments,
    },
  });
};
