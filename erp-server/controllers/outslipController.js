const db = require('../config/db');
const { TABLES } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');
const tp = require('../services/transactionPresenter');
const { loadOutslip } = require('../services/presentedRecords');
const { resolveLinesFromReceiving, enrichOutslipDetailLines } = require('../services/outslipLines');

exports.show = async (req, res) => {
  const { id } = req.params;
  try {
    const data = await loadOutslip(id);
    if (!data) return res.status(404).json({ message: 'Outslip not found.' });
    return res.json({ data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.index = async (req, res) => {
  try {
    const [outslips] = await db.query(`SELECT * FROM ${TABLES.OUTSLIP_MAIN} ORDER BY id DESC`);
    const [details] = await db.query(`SELECT * FROM ${TABLES.OUTSLIP_DETAILS}`);
    const [gatePasses] = await db.query(`SELECT * FROM ${TABLES.GATE_PASS}`);
    const [receivings] = await db.query(`SELECT id, receiving_no FROM ${TABLES.RECEIVING_MAIN}`);
    const gateByOutslip = new Map(gatePasses.map((g) => [g.outslip_id, g]));
    const receivingById = new Map(receivings.map((r) => [r.id, r]));

    const mapped = await Promise.all(
      outslips.map(async (os) => {
        const rawLines = details.filter((d) => d.outslip_id === os.id);
        const lines = await enrichOutslipDetailLines(os, rawLines);
        return tp.outslip(os, lines, gateByOutslip.get(os.id), receivingById.get(os.receiving_id));
      })
    );

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { customerId, receivingId } = req.body;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[rcv]] = await conn.query(`SELECT * FROM ${TABLES.RECEIVING_MAIN} WHERE id = ?`, [receivingId]);
    const [[customer]] = await conn.query('SELECT * FROM setup_customer WHERE id = ?', [customerId]);
    const [[latestOs]] = await conn.query(
      `SELECT outslip_no FROM ${TABLES.OUTSLIP_MAIN} ORDER BY id DESC LIMIT 1`
    );
    const osNo = nextDocumentNumber('OS-', latestOs?.outslip_no);

    const [result] = await conn.query(
      `INSERT INTO ${TABLES.OUTSLIP_MAIN} (customer_id, customer_name, outslip_no, outslip_date, receiving_id, branch_id, status)
       VALUES (?, ?, ?, NOW(), ?, 1, 'PENDING')`,
      [customer.id, customer.name, osNo, rcv.id]
    );

    const osId = result.insertId;
    const resolvedLines = await resolveLinesFromReceiving(rcv.id, conn);

    for (const line of resolvedLines) {
      await conn.query(
        `INSERT INTO ${TABLES.OUTSLIP_DETAILS} (outslip_id, item_id, item_name, qty, price, amount)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [osId, line.item_id, line.item_name, line.qty, line.price, line.amount]
      );
    }

    await conn.commit();
    const data = await loadOutslip(osId);
    return res.status(201).json({
      message: 'Outslip created successfully.',
      data,
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.approve = async (req, res) => {
  const { id } = req.params;
  try {
    await db.query(
      `UPDATE ${TABLES.OUTSLIP_MAIN} SET status = "APPROVED" WHERE id = ? OR outslip_no = ?`,
      [id, id]
    );
    const data = await loadOutslip(id);
    return res.json({ message: 'Outslip approved.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.dispatch = async (req, res) => {
  const { id } = req.params;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[os]] = await conn.query(
      `SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`,
      [id, id]
    );
    const [lines] = await conn.query(
      `SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`,
      [os.id]
    );

    for (const line of lines) {
      await conn.query(
        `INSERT INTO ${TABLES.INVENTORY} (branch_id, item_id, trans_id, trans_date, trans_type, \`in\`, \`out\`)
         VALUES (1, ?, ?, NOW(), 'OUTSLIP', 0, ?)`,
        [line.item_id, os.id, line.qty]
      );
    }

    await conn.query(`UPDATE ${TABLES.OUTSLIP_MAIN} SET status = "FOR_DISPATCH" WHERE id = ?`, [os.id]);
    await conn.commit();

    const data = await loadOutslip(os.id);
    return res.json({ message: 'Outslip marked for dispatch.', data });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.showGatePass = async (req, res) => {
  const { id } = req.params;
  try {
    const [[os]] = await db.query(
      `SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`,
      [id, id]
    );
    const [gpRows] = await db.query(`SELECT * FROM ${TABLES.GATE_PASS} WHERE outslip_id = ?`, [os.id]);
    const gp = gpRows[0] || {};
    const [lines] = await db.query(
      `SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`,
      [os.id]
    );

    return res.json({
      data: {
        gatePassNo: gp.gate_pass_no || `GP-${os.id}`,
        outslipNo: os.outslip_no,
        customerName: os.customer_name,
        destination: gp.destination || '',
        driverName: gp.driver_name || '',
        plateNo: gp.plate_no || '',
        vehicleNo: gp.vehicle_no || '',
        remarks: gp.remarks || '',
        status: (gp.status || 'PENDING').toLowerCase(),
        items: lines.map((l) => ({ productName: l.item_name, quantity: l.qty })),
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.saveGatePass = async (req, res) => {
  const { id } = req.params;
  const { vehicleNo, driverName, plateNo, destination, remarks } = req.body;
  try {
    const [[os]] = await db.query(`SELECT id FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`, [id, id]);
    await db.query(
      `INSERT INTO ${TABLES.GATE_PASS} (outslip_id, vehicle_no, driver_name, plate_no, destination, remarks, status, prepared_by)
       VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0)
       ON DUPLICATE KEY UPDATE 
       vehicle_no = VALUES(vehicle_no), driver_name = VALUES(driver_name),
       plate_no = VALUES(plate_no), destination = VALUES(destination), remarks = VALUES(remarks)`,
      [os.id, vehicleNo, driverName, plateNo, destination, remarks]
    );
    return res.json({ message: 'Gate pass saved.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.submit = async (req, res) => {
  const { id } = req.params;
  try {
    await db.query(
      `UPDATE ${TABLES.OUTSLIP_MAIN} SET status = "PENDING" WHERE id = ? OR outslip_no = ?`,
      [id, id]
    );
    const data = await loadOutslip(id);
    return res.json({ message: 'Outslip submitted for approval.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.voidGatePass = async (req, res) => {
  const { id } = req.params;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[os]] = await conn.query(
      `SELECT id, status FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`,
      [id, id]
    );
    const [[dr]] = await conn.query(
      `SELECT id FROM ${TABLES.DELIVERY_MAIN} WHERE outslip_id = ? LIMIT 1`,
      [os.id]
    );
    if (dr) {
      return res.status(422).json({ message: 'Cannot void a gate pass after a delivery receipt exists.' });
    }

    if (os.status === 'FOR_DISPATCH' || os.status === 'RELEASED') {
      await conn.query(`DELETE FROM ${TABLES.INVENTORY} WHERE trans_type = "OUTSLIP" AND trans_id = ?`, [os.id]);
      await conn.query(`UPDATE ${TABLES.OUTSLIP_MAIN} SET status = "APPROVED" WHERE id = ?`, [os.id]);
    }

    await conn.query(`UPDATE ${TABLES.GATE_PASS} SET status = "VOID" WHERE outslip_id = ?`, [os.id]);
    await conn.commit();

    return res.json({ message: 'Gate pass voided.' });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.markGatePassExit = async (req, res) => {
  const { id } = req.params;
  try {
    const [[os]] = await db.query(`SELECT id FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ? OR outslip_no = ?`, [id, id]);
    await db.query(
      `UPDATE ${TABLES.GATE_PASS} SET status = "EXITED", exit_at = NOW() WHERE outslip_id = ?`,
      [os.id]
    );
    return res.json({ message: 'Gate pass marked as exited.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};
