const db = require('../config/db');
const { TABLES } = require('../config/schema');

async function authenticateApiToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Unauthenticated.' });
  }

  const plainTextToken = authHeader.split(' ')[1];

  try {
    const [tokens] = await db.query(
      `SELECT * FROM ${TABLES.API_TOKENS} WHERE token = ? LIMIT 1`,
      [plainTextToken]
    );

    if (tokens.length === 0) {
      return res.status(401).json({ message: 'Unauthenticated.' });
    }

    const token = tokens[0];
    const [users] = await db.query(
      `SELECT * FROM ${TABLES.SETUP_USERS} WHERE id = ? LIMIT 1`,
      [token.setup_user_id]
    );

    if (users.length === 0 || users[0].status?.toUpperCase() === 'INACTIVE') {
      return res.status(401).json({ message: 'Unauthenticated.' });
    }

    const user = users[0];
    await db.query(`UPDATE ${TABLES.API_TOKENS} SET last_used_at = NOW() WHERE id = ?`, [token.id]);

    req.authUser = {
      id: user.id,
      name: user.name,
      username: user.username,
      role: (user.type || 'USER').toLowerCase(),
      isAdmin: (user.type || '').toUpperCase() === 'ADMIN',
    };
    req.authToken = token;

    next();
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
}

function ensureAdmin(req, res, next) {
  if (!req.authUser || !req.authUser.isAdmin) {
    return res.status(403).json({ message: 'Forbidden. Admin access required.' });
  }
  next();
}

module.exports = { authenticateApiToken, ensureAdmin };
