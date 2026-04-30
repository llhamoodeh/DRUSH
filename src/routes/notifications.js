const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT id, userid, [datetime] AS datetime, massege
      FROM dbo.[notifications]
      ORDER BY id DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .query('SELECT id, userid, [datetime] AS datetime, massege FROM dbo.[notifications] WHERE id = @id');

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'notification not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { userid, datetime, massege } = req.body;

  if (!userid || !massege) {
    return res.status(400).json({ message: 'userid and massege are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(userid))
      .input('datetime', sql.DateTime2, datetime || null)
      .input('massege', sql.NVarChar(sql.MAX), massege)
      .query(`
        INSERT INTO dbo.[notifications] (userid, [datetime], massege)
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.[datetime] AS datetime, INSERTED.massege
        VALUES (@userid, ISNULL(@datetime, SYSUTCDATETIME()), @massege)
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { userid, datetime, massege } = req.body;

  if (!userid || !massege) {
    return res.status(400).json({ message: 'userid and massege are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .input('userid', sql.Int, Number(userid))
      .input('datetime', sql.DateTime2, datetime || null)
      .input('massege', sql.NVarChar(sql.MAX), massege)
      .query(`
        UPDATE dbo.[notifications]
        SET userid = @userid,
            [datetime] = ISNULL(@datetime, [datetime]),
            massege = @massege
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.[datetime] AS datetime, INSERTED.massege
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'notification not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .query('DELETE FROM dbo.[notifications] WHERE id = @id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'notification not found.' });
    }

    return res.json({ message: 'notification deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
