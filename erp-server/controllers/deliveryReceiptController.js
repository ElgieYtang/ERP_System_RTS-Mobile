const db = require('../config/db');
const { TABLES } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');
const tp = require('../services/transactionPresenter');
const { loadDelivery } = require('../services/presentedRecords');
const { enrichOutslipDetailLines, enrichDeliveryDetailLines } = require('../services/outslipLines');

async function setupItemsMap(itemIds) {
  const ids = [...new Set(itemIds.filter(Boolean))];
  if (ids.length === 0) return new Map();
  const [rows] = await db.query('SELECT id, item_name, barcode FROM setup_items WHERE id IN (?)', [ids]);
  return new Map(rows.map((r) => [r.id, r]));
}

exports.show = async (req, res) => {
  const { id } = req.params;
  try {
    const data = await loadDelivery(id);
    if (!data) return res.status(404).json({ message: 'Delivery receipt not found.' });
    return res.json({ data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.index = async (req, res) => {
  try {
    const [deliveries] = await db.query(`SELECT * FROM ${TABLES.DELIVERY_MAIN} ORDER BY id DESC`);
    const [details] = await db.query(`SELECT * FROM ${TABLES.DELIVERY_DETAILS}`);
    const [outslips] = await db.query(`SELECT id, outslip_no FROM ${TABLES.OUTSLIP_MAIN}`);
    const outslipById = new Map(outslips.map((o) => [o.id, o]));
    const setupItemsById = await setupItemsMap(details.map((d) => d.item_id));

    const mapped = await Promise.all(
      deliveries.map(async (dr) => {
        const drDetails = details.filter((d) => Number(d.delivery_id) === Number(dr.id));
        const lines = await enrichDeliveryDetailLines(dr, drDetails);
        return tp.deliveryReceipt(
          dr,
          lines,
          outslipById.get(dr.outslip_id),
          setupItemsById
        );
      })
    );

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { outslipId } = req.body;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[os]] = await conn.query(`SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ?`, [outslipId]);
    const [[latestDr]] = await conn.query(
      `SELECT dr_no FROM ${TABLES.DELIVERY_MAIN} ORDER BY id DESC LIMIT 1`
    );
    const drNo = nextDocumentNumber('DR-', latestDr?.dr_no);

    const [result] = await conn.query(
      `INSERT INTO ${TABLES.DELIVERY_MAIN} (outslip_id, dr_no, dr_date, customer_id, customer_name, status)
       VALUES (?, ?, NOW(), ?, ?, 'ACTIVE')`,
      [os.id, drNo, os.customer_id, os.customer_name]
    );

    const drId = result.insertId;
    const [osLinesRaw] = await conn.query(
      `SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`,
      [os.id]
    );
    const osLines = await enrichOutslipDetailLines(os, osLinesRaw);
    let total = 0;
    for (const line of osLines) {
      const price = parseFloat(line.price || 0);
      const amount = Math.round(parseFloat(line.qty) * price * 100) / 100;
      total += amount;
      await conn.query(
        `INSERT INTO ${TABLES.DELIVERY_DETAILS} (delivery_id, item_id, item_name, qty, price, amount) VALUES (?, ?, ?, ?, ?, ?)`,
        [drId, line.item_id, line.item_name, line.qty, price, amount]
      );
    }
    await conn.query(`UPDATE ${TABLES.DELIVERY_MAIN} SET dr_total = ? WHERE id = ?`, [total, drId]);

    await conn.commit();
    const data = await loadDelivery(drId);
    return res.status(201).json({
      message: 'Delivery receipt created.',
      data,
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.updateSerials = async (req, res) => {
  const { id } = req.params;
  const serials = req.body.lines || req.body.serials || [];

  try {
    const [[dr]] = await db.query(
      `SELECT id FROM ${TABLES.DELIVERY_MAIN} WHERE id = ? OR dr_no = ?`,
      [id, id]
    );
    for (const entry of serials) {
      await db.query(
        `UPDATE ${TABLES.DELIVERY_DETAILS} SET serial_no = ? WHERE delivery_id = ? AND item_id = ?`,
        [entry.serialNumbers?.join(', ') || '', dr.id, entry.productId]
      );
    }
    const data = await loadDelivery(dr.id);
    return res.json({ message: 'Serial numbers updated.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.updateStatus = async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  const dbStatus = String(status || 'active').toUpperCase().replace(/_/g, ' ');

  try {
    await db.query(
      `UPDATE ${TABLES.DELIVERY_MAIN} SET status = ? WHERE id = ? OR dr_no = ?`,
      [dbStatus, id, id]
    );
    const data = await loadDelivery(id);
    return res.json({ message: 'Delivery status updated.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};
