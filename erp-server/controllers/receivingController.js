const db = require('../config/db');
const { TABLES } = require('../config/schema');
const tp = require('../services/transactionPresenter');
const { loadReceiving } = require('../services/presentedRecords');

exports.index = async (req, res) => {
  try {
    const [receivings] = await db.query(
      `SELECT r.*, po.supplier_name, po.supplier_id, po.po_no, q.customer_id, q.customer_name 
       FROM ${TABLES.RECEIVING_MAIN} r
       LEFT JOIN ${TABLES.PO_MAIN} po ON r.po_id = po.id
       LEFT JOIN ${TABLES.QUOTATION_MAIN} q ON po.quotation_id = q.id
       ORDER BY r.id DESC`
    );
    const [details] = await db.query(`SELECT * FROM ${TABLES.RECEIVING_DETAILS}`);
    const [pos] = await db.query(`SELECT * FROM ${TABLES.PO_MAIN}`);
    const [poDetails] = await db.query(`SELECT * FROM ${TABLES.PO_DETAILS}`);
    const poById = new Map(pos.map((p) => [p.id, p]));

    const mapped = receivings.map((r) => {
      const po = poById.get(r.po_id);
      const lines = details.filter((d) => d.receiving_id === r.id);
      const poLines = po ? poDetails.filter((d) => d.po_id === po.id) : [];
      return tp.receiving(r, lines, po, poLines, null);
    });

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.confirm = async (req, res) => {
  const { id } = req.params;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[rcv]] = await conn.query(
      `SELECT * FROM ${TABLES.RECEIVING_MAIN} WHERE id = ? OR receiving_no = ?`,
      [id, id]
    );
    if (!rcv) return res.status(404).json({ message: 'Receiving not found.' });

    const [lines] = await conn.query(
      `SELECT * FROM ${TABLES.RECEIVING_DETAILS} WHERE receiving_id = ?`,
      [rcv.id]
    );
    for (const line of lines) {
      await conn.query(
        `INSERT INTO ${TABLES.INVENTORY} (branch_id, item_id, trans_id, trans_date, trans_type, \`in\`, \`out\`)
         VALUES (?, ?, ?, NOW(), 'RECEIVING', ?, 0)`,
        [rcv.branch_id || 1, line.item_id, rcv.id, line.qty]
      );
    }

    await conn.query(`UPDATE ${TABLES.RECEIVING_MAIN} SET status = "COMPLETED" WHERE id = ?`, [rcv.id]);
    if (rcv.po_id) {
      await conn.query(`UPDATE ${TABLES.PO_MAIN} SET status = "COMPLETED" WHERE id = ?`, [rcv.po_id]);
    }

    await conn.commit();
    const data = await loadReceiving(rcv.id);
    return res.json({ message: 'Receiving confirmed.', data });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};
