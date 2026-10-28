const db = require('../config/db');
const { TABLES } = require('../config/schema');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

exports.login = async (req, res) => {
  const { login, password } = req.body;
  if (!login || !password) {
    return res.status(422).json({ message: 'Invalid username or password.' });
  }

  const username = login.trim().toLowerCase() === 'admin@responsivcode.com' ? 'admin' : login.trim();

  try {
    const [users] = await db.query(
      `SELECT * FROM ${TABLES.SETUP_USERS} WHERE username = ? LIMIT 1`,
      [username]
    );

    if (users.length === 0) {
      return res.status(422).json({ message: 'Invalid username or password.' });
    }

    const user = users[0];
    const passwordMatch = bcrypt.compareSync(password, user.password) || password === user.password;

    if (!passwordMatch || user.status?.toUpperCase() === 'INACTIVE') {
      return res.status(422).json({ message: 'Invalid username or password.' });
    }

    const plainTextToken = crypto.randomBytes(32).toString('hex');
    await db.query(
      `INSERT INTO ${TABLES.API_TOKENS} (setup_user_id, name, token, created_at, updated_at) VALUES (?, ?, ?, NOW(), NOW())`,
      [user.id, 'mobile', plainTextToken]
    );

    return res.json({
      token: plainTextToken,
      token_type: 'Bearer',
      user: {
        id: user.id,
        name: user.name,
        login: user.username,
        role: (user.type || 'USER').toLowerCase(),
      },
    });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
};

exports.me = (req, res) => {
  return res.json({ user: req.authUser });
};

exports.logout = async (req, res) => {
  try {
    if (req.authToken) {
      await db.query(`DELETE FROM ${TABLES.API_TOKENS} WHERE id = ?`, [req.authToken.id]);
    }
    return res.json({ message: 'Logged out successfully.' });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
};
