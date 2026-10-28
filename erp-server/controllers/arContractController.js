const db = require('../config/db');
const { TABLES } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');

exports.index = async (req, res) => {
  try {
    const [contracts] = await db.query('SELECT * FROM ar_contracts ORDER BY id DESC');
    return res.json({ data: contracts });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { customerId, projectId, contractAmount, monthlyFee, startDate, endDate, billingDay } = req.body;
  try {
    const [[latest]] = await db.query('SELECT contract_no FROM ar_contracts ORDER BY id DESC LIMIT 1');
    const contractNo = nextDocumentNumber('CON-', latest?.contract_no);

    const [result] = await db.query(
      `INSERT INTO ar_contracts 
       (contract_no, customer_id, project_id, contract_amount, monthly_fee, start_date, end_date, billing_day, status) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE')`,
      [contractNo, customerId, projectId || null, contractAmount || 0, monthlyFee || 0, startDate || null, endDate || null, billingDay || 1]
    );

    return res.status(201).json({
      message: 'AR Contract created.',
      data: { id: contractNo, dbId: String(result.insertId) },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.show = async (req, res) => {
  const { id } = req.params;
  try {
    const [[contract]] = await db.query('SELECT * FROM ar_contracts WHERE id = ? OR contract_no = ?', [id, id]);
    if (!contract) return res.status(404).json({ message: 'Contract not found.' });

    const [lines] = await db.query(
      `SELECT * FROM ${TABLES.AR_CONTRACT_LINES} WHERE ar_contract_id = ?`,
      [contract.id]
    );
    return res.json({ data: { ...contract, lines } });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.update = async (req, res) => {
  const { id } = req.params;
  const { contractAmount, monthlyFee, startDate, endDate, billingDay, status } = req.body;
  try {
    await db.query(
      `UPDATE ar_contracts SET 
       contract_amount = COALESCE(?, contract_amount),
       monthly_fee = COALESCE(?, monthly_fee),
       start_date = COALESCE(?, start_date),
       end_date = COALESCE(?, end_date),
       billing_day = COALESCE(?, billing_day),
       status = COALESCE(?, status)
       WHERE id = ? OR contract_no = ?`,
      [contractAmount, monthlyFee, startDate, endDate, billingDay, status, id, id]
    );
    return res.json({ message: 'Contract updated.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.destroy = async (req, res) => {
  const { id } = req.params;
  try {
    await db.query('UPDATE ar_contracts SET status = "INACTIVE" WHERE id = ? OR contract_no = ?', [id, id]);
    return res.json({ message: 'Contract deactivated.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.storeLine = async (req, res) => {
  const { id } = req.params;
  const { accountLabel, monthlyFee } = req.body;
  try {
    const [[contract]] = await db.query('SELECT id FROM ar_contracts WHERE id = ? OR contract_no = ?', [id, id]);
    const [result] = await db.query(
      `INSERT INTO ${TABLES.AR_CONTRACT_LINES} (ar_contract_id, account_label, monthly_fee) VALUES (?, ?, ?)`,
      [contract.id, accountLabel, monthlyFee]
    );
    return res.status(201).json({ message: 'Line added.', data: { id: result.insertId, accountLabel, monthlyFee } });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.updateLine = async (req, res) => {
  const { lineId } = req.params;
  const { accountLabel, monthlyFee } = req.body;
  try {
    await db.query(
      `UPDATE ${TABLES.AR_CONTRACT_LINES} SET account_label = COALESCE(?, account_label), monthly_fee = COALESCE(?, monthly_fee) WHERE id = ?`,
      [accountLabel, monthlyFee, lineId]
    );
    return res.json({ message: 'Line updated.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.destroyLine = async (req, res) => {
  const { lineId } = req.params;
  try {
    await db.query(`DELETE FROM ${TABLES.AR_CONTRACT_LINES} WHERE id = ?`, [lineId]);
    return res.json({ message: 'Line deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};