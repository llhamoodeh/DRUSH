const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

function decodeDateParam(value) {
  return decodeURIComponent(value);
}

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips
      FROM dbo.[schedule]
      ORDER BY startdatetime DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:userid/:groupid/:startdatetime', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.params.userid))
      .input('groupid', sql.Int, Number(req.params.groupid))
      .input('startdatetime', sql.DateTime2, decodeDateParam(req.params.startdatetime))
      .query(`
        SELECT userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips
        FROM dbo.[schedule]
        WHERE userid = @userid AND groupid = @groupid AND startdatetime = @startdatetime
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips } = req.body;

  if (!userid || !groupid || !startdatetime || !enddatetime || !createdby) {
    return res.status(400).json({
      message: 'userid, groupid, startdatetime, enddatetime and createdby are required.'
    });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(userid))
      .input('groupid', sql.Int, Number(groupid))
      .input('startdatetime', sql.DateTime2, startdatetime)
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        INSERT INTO dbo.[schedule] (userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips)
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        VALUES (
          @userid,
          @groupid,
          @startdatetime,
          @enddatetime,
          ISNULL(@creeatedat, SYSUTCDATETIME()),
          @createdby,
          @tips
        )
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:userid/:groupid/:startdatetime', async (req, res) => {
  const { enddatetime, creeatedat, createdby, tips } = req.body;

  if (!enddatetime || !createdby) {
    return res.status(400).json({ message: 'enddatetime and createdby are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.params.userid))
      .input('groupid', sql.Int, Number(req.params.groupid))
      .input('startdatetime', sql.DateTime2, decodeDateParam(req.params.startdatetime))
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        UPDATE dbo.[schedule]
        SET enddatetime = @enddatetime,
            creeatedat = ISNULL(@creeatedat, creeatedat),
            createdby = @createdby,
            tips = @tips
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        WHERE userid = @userid AND groupid = @groupid AND startdatetime = @startdatetime
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:userid/:groupid/:startdatetime', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.params.userid))
      .input('groupid', sql.Int, Number(req.params.groupid))
      .input('startdatetime', sql.DateTime2, decodeDateParam(req.params.startdatetime))
      .query('DELETE FROM dbo.[schedule] WHERE userid = @userid AND groupid = @groupid AND startdatetime = @startdatetime');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json({ message: 'schedule item deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
