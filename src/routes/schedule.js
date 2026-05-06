const express = require('express');
const { sql, getPool } = require('../config/db');
const {
  completionUpload,
  getSingleFile,
  validateTaskCompletion
} = require('../services/taskPhotoValidation');

const router = express.Router();

let ensureScheduleTablePromise;
let ensureCompletionTablePromise;
let ensureCoinsColumnPromise;

async function ensureScheduleTable() {
  if (!ensureScheduleTablePromise) {
    const pool = await getPool();
    ensureScheduleTablePromise = pool.request().query(`
      IF COL_LENGTH('dbo.schedule', 'id') IS NULL
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD id INT IDENTITY(1,1) NOT NULL
      END

      IF COL_LENGTH('dbo.schedule', 'penalized') IS NULL
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD penalized BIT NOT NULL DEFAULT 0
      END

      IF NOT EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE type = 'PK'
          AND parent_object_id = OBJECT_ID('dbo.schedule')
      )
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD CONSTRAINT PK_schedule_id PRIMARY KEY (id)
      END
    `);
  }

  await ensureScheduleTablePromise;
}

async function ensureCoinsColumn() {
  if (!ensureCoinsColumnPromise) {
    const pool = await getPool();
    ensureCoinsColumnPromise = pool.request().query(`
      IF NOT EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'users'
          AND COLUMN_NAME = 'coins'
      )
      BEGIN
        ALTER TABLE dbo.[users]
        ADD coins INT NOT NULL DEFAULT 0
      END
    `);
  }

  await ensureCoinsColumnPromise;
}

async function applyOverduePenalties(pool, userId) {
  const request = pool.request().input('now', sql.DateTime2, new Date());

  if (Number.isFinite(userId)) {
    request.input('userid', sql.Int, userId);
  }

  await request.query(`
    DECLARE @overdue TABLE (id INT, userid INT);

    INSERT INTO @overdue (id, userid)
    SELECT s.id, s.userid
    FROM dbo.[schedule] s
    LEFT JOIN dbo.[schedule_completions] c
      ON c.userid = s.userid
     AND c.startdatetime = s.startdatetime
     AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
    WHERE s.enddatetime < @now
      AND (s.penalized = 0 OR s.penalized IS NULL)
      AND c.userid IS NULL
      ${Number.isFinite(userId) ? 'AND s.userid = @userid' : ''};

    UPDATE u
    SET coins = coins - (o.cnt * 10)
    FROM dbo.[users] u
    INNER JOIN (
      SELECT userid, COUNT(*) AS cnt
      FROM @overdue
      GROUP BY userid
    ) o ON o.userid = u.id;

    UPDATE s
    SET penalized = 1
    FROM dbo.[schedule] s
    INNER JOIN @overdue o ON o.id = s.id;
  `);
}

async function ensureCompletionTable() {
  await ensureScheduleTable();
  if (!ensureCompletionTablePromise) {
    const pool = await getPool();
    ensureCompletionTablePromise = pool.request().query(`
      IF OBJECT_ID('dbo.schedule_completions', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[schedule_completions] (
          userid INT NOT NULL,
          groupid INT NOT NULL,
          startdatetime DATETIME2 NOT NULL,
          completedby INT NOT NULL,
          completedat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
          PRIMARY KEY (userid, groupid, startdatetime)
        )
      END
    `);
  }

  await ensureCompletionTablePromise;
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

router.get('/', async (req, res) => {
  const userId = Number(req.user?.id);

  if (!Number.isFinite(userId)) {
    return res.status(401).json({ message: 'Unauthorized.' });
  }

  try {
    await ensureScheduleTable();
    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    await applyOverduePenalties(pool, userId);
    const result = await pool
      .request()
      .input('userid', sql.Int, userId)
      .query(`
      SELECT
        s.id,
        s.userid,
        s.groupid,
        s.startdatetime,
        s.enddatetime,
        s.creeatedat,
        s.createdby,
        s.tips,
        c.completedat,
        c.completedby
      FROM dbo.[schedule] s
      LEFT JOIN dbo.[schedule_completions] c
        ON c.userid = s.userid
       AND c.startdatetime = s.startdatetime
       AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
      WHERE s.userid = @userid
         OR (
           s.groupid IS NOT NULL
           AND s.groupid <> 0
           AND EXISTS (
             SELECT 1
             FROM dbo.[grouppart] gp
             WHERE gp.groupid = s.groupid
               AND gp.userid = @userid
           )
         )
      ORDER BY s.startdatetime DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);
  const userId = Number(req.user?.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  if (!Number.isFinite(userId)) {
    return res.status(401).json({ message: 'Unauthorized.' });
  }

  try {
    await ensureScheduleTable();
    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    await applyOverduePenalties(pool, userId);
    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .input('userid', sql.Int, userId)
      .query(`
        SELECT
          s.id,
          s.userid,
          s.groupid,
          s.startdatetime,
          s.enddatetime,
          s.creeatedat,
          s.createdby,
          s.tips,
          c.completedat,
          c.completedby
        FROM dbo.[schedule] s
        LEFT JOIN dbo.[schedule_completions] c
          ON c.userid = s.userid
         AND c.startdatetime = s.startdatetime
         AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
        WHERE s.id = @id
          AND (
            s.userid = @userid
            OR (
              s.groupid IS NOT NULL
              AND s.groupid <> 0
              AND EXISTS (
                SELECT 1
                FROM dbo.[grouppart] gp
                WHERE gp.groupid = s.groupid
                  AND gp.userid = @userid
              )
            )
          )
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
    await ensureScheduleTable();
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
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
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

router.put('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);
  const { userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips } = req.body;

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  if (!userid || !startdatetime || !enddatetime || !createdby) {
    return res.status(400).json({ message: 'userid, startdatetime, enddatetime and createdby are required.' });
  }

  try {
    await ensureScheduleTable();
    const pool = await getPool();
    const normalizedGroupId = parseNullableGroupId(groupid);
    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .input('userid', sql.Int, Number(userid))
      .input('groupid', sql.Int, normalizedGroupId)
      .input('startdatetime', sql.DateTime2, startdatetime)
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        UPDATE dbo.[schedule]
        SET userid = @userid,
            groupid = @groupid,
            startdatetime = @startdatetime,
            enddatetime = @enddatetime,
            creeatedat = ISNULL(@creeatedat, creeatedat),
            createdby = @createdby,
            tips = @tips
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureScheduleTable();
    await ensureCompletionTable();
    const pool = await getPool();
    
    // Get the schedule first to find its userid, groupid, startdatetime
    const scheduleResult = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`SELECT userid, groupid, startdatetime FROM dbo.[schedule] WHERE id = @id`);
    
    if (scheduleResult.recordset.length > 0) {
      const sched = scheduleResult.recordset[0];
      await pool
        .request()
        .input('userid', sql.Int, sched.userid)
        .input('groupid', sql.Int, sched.groupid ?? 0)
        .input('startdatetime', sql.DateTime2, sched.startdatetime)
        .query(`
          DELETE FROM dbo.[schedule_completions]
          WHERE userid = @userid
            AND groupid = @groupid
            AND startdatetime = @startdatetime
        `);
    }

    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        DELETE FROM dbo.[schedule]
        WHERE id = @id
      `);

    if (result.rowsAffected[0] > 0) {
      return res.json({ message: 'schedule item deleted.' });
    }

    return res.status(404).json({ message: 'schedule item not found.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post(
  '/:id/complete',
  completionUpload.fields([
    { name: 'beforePhoto', maxCount: 1 },
    { name: 'afterPhoto', maxCount: 1 }
  ]),
  async (req, res) => {
    const scheduleId = Number(req.params.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    const scheduleResult = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        SELECT id, userid, groupid, startdatetime, enddatetime, tips
        FROM dbo.[schedule]
        WHERE id = @id
      `);

    if (scheduleResult.recordset.length === 0) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const schedule = scheduleResult.recordset[0];
    const taskUserId = Number(schedule.userid);
    const scheduleGroupId = schedule.groupid ?? 0;

    if (Number(req.user?.id) !== taskUserId) {
      return res.status(403).json({ message: 'You can only complete your own tasks.' });
    }

    if (schedule.groupid !== null) {
      return res.status(400).json({ message: 'Group tasks must be completed through the group endpoint.' });
    }

    const existingResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, scheduleGroupId)
      .input('startdatetime', sql.DateTime2, schedule.startdatetime)
      .query(`
        SELECT userid, groupid, startdatetime, completedby, completedat
        FROM dbo.[schedule_completions]
        WHERE userid = @userid
          AND groupid = @groupid
          AND startdatetime = @startdatetime
      `);

    if (existingResult.recordset.length > 0) {
      return res.json(existingResult.recordset[0]);
    }

    const completionTime = new Date();
    const deadline = new Date(schedule.enddatetime);

    if (completionTime > deadline) {
      return res.status(400).json({ message: 'Cannot complete task after the deadline.' });
    }

    const validation = await validateTaskCompletion({
      taskDescription: schedule.tips || '',
      beforePhoto: getSingleFile(req.files, 'beforePhoto'),
      afterPhoto: getSingleFile(req.files, 'afterPhoto')
    });

    if (!validation.ok) {
      return res
        .status(validation.status || 400)
        .json({ message: validation.message || 'Task completion could not be verified.' });
    }

    const coinsChange = 10;
    const insertResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, scheduleGroupId)
      .input('startdatetime', sql.DateTime2, schedule.startdatetime)
      .input('completedby', sql.Int, taskUserId)
      .input('coinsChange', sql.Int, coinsChange)
      .query(`
        INSERT INTO dbo.[schedule_completions] (userid, groupid, startdatetime, completedby, completedat)
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.completedby, INSERTED.completedat
        VALUES (@userid, @groupid, @startdatetime, @completedby, SYSUTCDATETIME())

        UPDATE dbo.[users]
        SET coins = coins + @coinsChange
        WHERE id = @userid
      `);

    return res.json({ message: 'Congrats! 🎉🎊', completion: insertResult.recordset[0] });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
