const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { sql, getPool } = require('../config/db');

const router = express.Router();

router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ message: 'email and password are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('email', sql.NVarChar(320), email)
      .query(`
        SELECT TOP 1 id, name, email, [password] AS password_hash
        FROM dbo.[users]
        WHERE email = @email
      `);

    if (result.recordset.length === 0) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    const user = result.recordset[0];

    let passwordMatches = false;
    try {
      passwordMatches = await bcrypt.compare(password, user.password_hash);
    } catch (err) {
      passwordMatches = false;
    }

    if (!passwordMatches) {
      passwordMatches = password === user.password_hash;
    }

    if (!passwordMatches) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email, name: user.name },
      process.env.JWT_SECRET || 'change-this-secret',
      { expiresIn: '7d' }
    );

    return res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email
      }
    });
  } catch (err) {
    if (typeof err.message === 'string' && err.message.includes("Login failed for user")) {
      return res.status(500).json({ message: 'Database authentication failed. Check DB_USER and DB_PASSWORD configuration.' });
    }

    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
