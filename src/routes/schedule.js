const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

function decodeDateParam(value) {
  return decodeURIComponent(value);
}

function tryParseDate(value) {
  if (!value) return null;
  const decoded = decodeDateParam(value);

  // Try direct Date parsing first
  let d = new Date(decoded);
  if (!isNaN(d.getTime())) return d;

  // Try removing trailing Z
  try {
    const withoutZ = decoded.replace(/Z$/, '');
    d = new Date(withoutZ);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  // Try removing fractional seconds
  try {
    const noFrac = decoded.replace(/\.\d{1,6}/, '');
    d = new Date(noFrac);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  // Try space instead of T
  try {
    const space = decoded.replace('T', ' ');
    d = new Date(space);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  return null;
}

function parseNullableGroupId(value) {
  if (value === undefined || value === null || value === '' || value === 'null') {
    return null;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed === 0) {
    return null;
  }

  return parsed;
}

async function findScheduleRow(pool, userid, groupid, startdatetimeParam) {
  const parsed = tryParseDate(startdatetimeParam);
  const raw = decodeDateParam(startdatetimeParam);
  const normalizedGroupId = parseNullableGroupId(groupid);
  const groupClause = normalizedGroupId === null
    ? 'groupid IS NULL'
    : 'groupid = @groupid';

  if (parsed) {
    const exactResult = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, normalizedGroupId)
      .input('startdatetime', sql.DateTime2, parsed)
      .query(`
        SELECT TOP 1 userid, groupid, startdatetime
        FROM dbo.[schedule]
        WHERE userid = @userid AND ${groupClause} AND startdatetime = @startdatetime
      `);

    if (exactResult.recordset.length > 0) {
      return exactResult.recordset[0];
    }
  }

  const stringResult = await pool
    .request()
    .input('userid', sql.Int, userid)
    .input('groupid', sql.Int, normalizedGroupId)
    .input('raw', sql.NVarChar(64), raw)
    .query(`
      SELECT TOP 1 userid, groupid, startdatetime
      FROM dbo.[schedule]
      WHERE userid = @userid
        AND ${groupClause}
        AND CONVERT(varchar(64), startdatetime, 126) = @raw
    `);

  if (stringResult.recordset.length > 0) {
    return stringResult.recordset[0];
  }

  if (!parsed) {
    return null;
  }

  const prefix = raw.replace(/\.\d{1,6}/, '').replace(/Z$/, '').slice(0, 19);
  const looseResult = await pool
    .request()
    .input('userid', sql.Int, userid)
    .input('groupid', sql.Int, normalizedGroupId)
    .input('prefix', sql.NVarChar(32), prefix)
    .query(`
      SELECT TOP 1 userid, groupid, startdatetime
      FROM dbo.[schedule]
      WHERE userid = @userid
        AND ${groupClause}
        AND CONVERT(varchar(19), startdatetime, 126) = @prefix
      ORDER BY startdatetime DESC
    `);

  return looseResult.recordset[0] || null;
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
    const parsed = tryParseDate(req.params.startdatetime);
    if (!parsed) {
      return res.status(400).json({ message: 'Invalid startdatetime.' });
    }

    const groupid = parseNullableGroupId(req.params.groupid);
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.params.userid))
      .input('groupid', sql.Int, groupid)
      .input('startdatetime', sql.DateTime2, parsed)
      .query(`
        SELECT userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips
        FROM dbo.[schedule]
        WHERE userid = @userid
          AND ((@groupid IS NULL AND groupid IS NULL) OR groupid = @groupid)
          AND startdatetime = @startdatetime
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
  const normalizedGroupId = parseNullableGroupId(groupid);

  if (!userid || !startdatetime || !enddatetime || !createdby) {
    return res.status(400).json({
      message: 'userid, startdatetime, enddatetime and createdby are required.'
    });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(userid))
      .input('groupid', sql.Int, normalizedGroupId)
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
    const userid = Number(req.params.userid);
    const groupid = parseNullableGroupId(req.params.groupid);
    const scheduleRow = await findScheduleRow(pool, userid, groupid, req.params.startdatetime);

    if (!scheduleRow) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    const result = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, scheduleRow.groupid ?? null)
      .input('startdatetime', sql.DateTime2, scheduleRow.startdatetime)
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
        WHERE userid = @userid
          AND ((@groupid IS NULL AND groupid IS NULL) OR groupid = @groupid)
          AND startdatetime = @startdatetime
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

    const userid = Number(req.params.userid);
    const groupid = parseNullableGroupId(req.params.groupid);
    const scheduleRow = await findScheduleRow(pool, userid, groupid, req.params.startdatetime);

    if (!scheduleRow) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    const result = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, scheduleRow.groupid ?? null)
      .input('startdatetime', sql.DateTime2, scheduleRow.startdatetime)
      .query(`
        DELETE FROM dbo.[schedule]
        WHERE userid = @userid
          AND ((@groupid IS NULL AND groupid IS NULL) OR groupid = @groupid)
          AND startdatetime = @startdatetime
      `);

    if (result.rowsAffected[0] > 0) {
      return res.json({ message: 'schedule item deleted.' });
    }

    return res.status(404).json({ message: 'schedule item not found.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
