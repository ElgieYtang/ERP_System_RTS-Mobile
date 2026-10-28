const db = require('../config/db');
const bcrypt = require('bcryptjs');
const { TABLES } = require('../config/schema');

const settingsTable = TABLES.SETTINGS;

exports.show = async (req, res) => {
  try {
    const [rows] = await db.query(`SELECT * FROM ${settingsTable} LIMIT 1`);
    const row = rows[0] || {};
    return res.json({
      data: {
        company_name: row.company_name,
        company_address: row.company_address,
        company_phone: row.company_phone,
        company_email: row.company_email,
        date_format: row.date_format,
        paper_size: row.paper_size,
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.update = async (req, res) => {
  const payload = req.body;
  const allowed = {
    company_name: 'company_name',
    company_address: 'company_address',
    company_phone: 'company_phone',
    company_email: 'company_email',
    date_format: 'date_format',
    paper_size: 'paper_size',
  };

  try {
    const [rows] = await db.query(`SELECT id FROM ${settingsTable} LIMIT 1`);
    if (rows.length === 0) {
      return res.status(404).json({ message: 'Settings row not found.' });
    }
    const settingsId = rows[0].id;

    for (const [key, val] of Object.entries(payload)) {
      const column = allowed[key];
      if (!column) continue;
      await db.query(`UPDATE ${settingsTable} SET ${column} = ?, updated_at = NOW() WHERE id = ?`, [
        String(val),
        settingsId,
      ]);
    }
    return res.json({ message: 'Settings updated successfully.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.updatePassword = async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  const userId = req.authUser.id;

  if (!newPassword || newPassword.length < 6) {
    return res.status(422).json({ message: 'New password must be at least 6 characters.' });
  }

  try {
    const [[user]] = await db.query(`SELECT password FROM ${TABLES.SETUP_USERS} WHERE id = ?`, [userId]);
    const matches = bcrypt.compareSync(currentPassword, user.password) || currentPassword === user.password;

    if (!matches) {
      return res.status(422).json({ message: 'Current password is incorrect.' });
    }

    const hashed = bcrypt.hashSync(newPassword, 10);
    await db.query(`UPDATE ${TABLES.SETUP_USERS} SET password = ? WHERE id = ?`, [hashed, userId]);

    return res.json({ message: 'Password updated successfully.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};
