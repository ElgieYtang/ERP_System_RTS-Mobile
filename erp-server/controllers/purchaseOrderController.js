const db = require('../config/db');
const { TABLES } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');
const tp = require('../services/transactionPresenter');
const { loadReceiving } = require('../services/presentedRecords');

exports.index = async (req, res) => {
  try {
    const [pos] = await db.query(`SELECT * FROM ${TABLES.PO_MAIN} ORDER BY id DESC`);
    const [details] = await db.query(`SELECT * FROM ${TABLES.PO_DETAILS}`);
    const [quotations] = await db.query(`SELECT id, quotation_no FROM ${TABLES.QUOTATION_MAIN}`);
    const quotationById = new Map(quotations.map((q) => [q.id, q]));

    const mapped = pos.map((po) =>
      tp.purchaseOrder(
        po,
        details.filter((d) => d.po_id === po.id),
        quotationById.get(po.quotation_id)
      )
    );

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.destroy = async (req, res) => {
  const { id } = req.params;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[po]] = await conn.query(
      `SELECT * FROM ${TABLES.PO_MAIN} WHERE id = ? OR po_no = ?`,
      [id, id]
    );
    if (!po) return res.status(404).json({ message: 'PO not found.' });

    const [[hasRcv]] = await conn.query(
      `SELECT id FROM ${TABLES.RECEIVING_MAIN} WHERE po_id = ? LIMIT 1`,
      [po.id]
    );
    if (hasRcv) {
      return res.status(422).json({ message: 'Cannot delete a purchase order that already has receiving records.' });
    }

    await conn.query('DELETE FROM supplier_ledger WHERE po_id = ?', [po.id]);
    await conn.query(`DELETE FROM ${TABLES.PO_DETAILS} WHERE po_id = ?`, [po.id]);
    await conn.query(`DELETE FROM ${TABLES.PO_MAIN} WHERE id = ?`, [po.id]);

    await conn.commit();
    return res.json({ message: 'Purchase order deleted successfully.' });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.createReceiving = async (req, res) => {
  const { id } = req.params;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[po]] = await conn.query(
      `SELECT * FROM ${TABLES.PO_MAIN} WHERE id = ? OR po_no = ?`,
      [id, id]
    );
    if (!po) return res.status(404).json({ message: 'Purchase Order not found.' });

    const [[latestRcv]] = await conn.query(
      `SELECT receiving_no FROM ${TABLES.RECEIVING_MAIN} ORDER BY id DESC LIMIT 1`
    );
    const rcvNo = nextDocumentNumber('RCV-', latestRcv?.receiving_no);

    const [rcvResult] = await conn.query(
      `INSERT INTO ${TABLES.RECEIVING_MAIN} (po_id, receiving_no, receiving_date, branch_id, status)
       VALUES (?, ?, NOW(), 1, 'PENDING')`,
      [po.id, rcvNo]
    );

    const rcvId = rcvResult.insertId;
    const [poLines] = await conn.query(`SELECT * FROM ${TABLES.PO_DETAILS} WHERE po_id = ?`, [po.id]);
    for (const line of poLines) {
      await conn.query(
        `INSERT INTO ${TABLES.RECEIVING_DETAILS} (receiving_id, item_id, qty) VALUES (?, ?, ?)`,
        [rcvId, line.item_id, line.qty]
      );
    }

    await conn.commit();
    const data = await loadReceiving(rcvId);
    return res.status(201).json({
      message: 'Receiving created.',
      data,
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};
