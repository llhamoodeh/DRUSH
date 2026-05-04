const express = require('express');
const { sql, getPool } = require('../config/db');

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

async function fetchGroup(pool, groupId) {
  const result = await pool
    .request()
    .input('id', sql.Int, groupId)
    .query(`
      SELECT id, name, creatorid, [creation date] AS creationDate
      FROM dbo.[groups]
      WHERE id = @id
    `);

  return result.recordset[0];
}

async function isGroupMember(pool, groupId, userId) {
  const result = await pool
    .request()
    .input('groupid', sql.Int, groupId)
    .input('userid', sql.Int, userId)
    .query('SELECT 1 FROM dbo.[grouppart] WHERE groupid = @groupid AND userid = @userid');

  return result.recordset.length > 0;
}

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT id, name, creatorid, [creation date] AS creationDate
      FROM dbo.[groups]
      ORDER BY id DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/mine', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.user?.id))
      .query(`
        SELECT g.id, g.name, g.creatorid, g.[creation date] AS creationDate
        FROM dbo.[groups] g
        INNER JOIN dbo.[grouppart] gp ON gp.groupid = g.id
        WHERE gp.userid = @userid
        ORDER BY g.id DESC
      `);

    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { name } = req.body;

  if (!name) {
    return res.status(400).json({ message: 'name is required.' });
  }

  try {
    const pool = await getPool();
    const creatorId = Number(req.user?.id);
    const transaction = new sql.Transaction(pool);

    await transaction.begin();
    try {
      const groupResult = await new sql.Request(transaction)
        .input('name', sql.NVarChar(255), name)
        .input('creatorid', sql.Int, creatorId)
        .query(`
          INSERT INTO dbo.[groups] (name, creatorid, [creation date])
          OUTPUT INSERTED.id, INSERTED.name, INSERTED.creatorid, INSERTED.[creation date] AS creationDate
          VALUES (@name, @creatorid, SYSUTCDATETIME())
        `);

      const group = groupResult.recordset[0];

      await new sql.Request(transaction)
        .input('groupid', sql.Int, group.id)
        .input('userid', sql.Int, creatorId)
        .query(`
          IF NOT EXISTS (
            SELECT 1 FROM dbo.[grouppart] WHERE groupid = @groupid AND userid = @userid
          )
          BEGIN
            INSERT INTO dbo.[grouppart] (groupid, userid)
            VALUES (@groupid, @userid)
          END
        `);

      await transaction.commit();
      return res.status(201).json(group);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/members', async (req, res) => {
  const groupId = Number(req.params.id);

  try {
    const pool = await getPool();
    const isMember = await isGroupMember(pool, groupId, Number(req.user?.id));

    if (!isMember) {
      return res.status(403).json({ message: 'Not a member of this group.' });
    }

    const result = await pool
      .request()
      .input('groupid', sql.Int, groupId)
      .query(`
        SELECT u.id, u.name, u.email
        FROM dbo.[grouppart] gp
        INNER JOIN dbo.[users] u ON u.id = gp.userid
        WHERE gp.groupid = @groupid
        ORDER BY u.name ASC
      `);

    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/members', async (req, res) => {
  const groupId = Number(req.params.id);
  const email = (req.body?.email || '').toString().trim();

  if (!email) {
    return res.status(400).json({ message: 'email is required.' });
  }

  try {
    const pool = await getPool();
    const group = await fetchGroup(pool, groupId);

    if (!group) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    if (group.creatorid !== Number(req.user?.id)) {
      return res.status(403).json({ message: 'Only the group creator can add members.' });
    }

    const userResult = await pool
      .request()
      .input('email', sql.NVarChar(320), email)
      .query('SELECT TOP 1 id, name, email FROM dbo.[users] WHERE email = @email');

    if (userResult.recordset.length === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const user = userResult.recordset[0];
    const memberExists = await isGroupMember(pool, groupId, user.id);

    if (memberExists) {
      return res.status(409).json({ message: 'User already in group.' });
    }

    await pool
      .request()
      .input('groupid', sql.Int, groupId)
      .input('userid', sql.Int, user.id)
      .query('INSERT INTO dbo.[grouppart] (groupid, userid) VALUES (@groupid, @userid)');

    return res.status(201).json(user);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id/members/:userid', async (req, res) => {
  const groupId = Number(req.params.id);
  const targetUserId = Number(req.params.userid);

  try {
    const pool = await getPool();
    const group = await fetchGroup(pool, groupId);

    if (!group) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    if (group.creatorid !== Number(req.user?.id)) {
      return res.status(403).json({ message: 'Only the group creator can remove members.' });
    }

    if (group.creatorid === targetUserId) {
      return res.status(400).json({ message: 'The creator cannot be removed.' });
    }

    const result = await pool
      .request()
      .input('groupid', sql.Int, groupId)
      .input('userid', sql.Int, targetUserId)
      .query('DELETE FROM dbo.[grouppart] WHERE groupid = @groupid AND userid = @userid');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'Member not found.' });
    }

    return res.json({ message: 'Member removed.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/tasks', async (req, res) => {
  const groupId = Number(req.params.id);

  try {
    await ensureCompletionTable();
    const pool = await getPool();
    const isMember = await isGroupMember(pool, groupId, Number(req.user?.id));

    if (!isMember) {
      return res.status(403).json({ message: 'Not a member of this group.' });
    }

    const result = await pool
      .request()
      .input('groupid', sql.Int, groupId)
      .query(`
        SELECT s.id, s.userid, s.groupid, s.startdatetime, s.enddatetime, s.creeatedat, s.createdby, s.tips,
               c.completedat, c.completedby
        FROM dbo.[schedule] s
        LEFT JOIN dbo.[schedule_completions] c
          ON c.userid = s.userid
         AND c.startdatetime = s.startdatetime
         AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
        WHERE s.groupid = @groupid
        ORDER BY s.startdatetime DESC
      `);

    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/tasks/:scheduleId/complete', async (req, res) => {
  const groupId = Number(req.params.id);
  const scheduleId = Number(req.params.scheduleId);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'scheduleId must be a number.' });
  }

  try {
    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    const scheduleResult = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        SELECT id, userid, groupid, startdatetime, enddatetime
        FROM dbo.[schedule]
        WHERE id = @id
      `);

    if (scheduleResult.recordset.length === 0) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const schedule = scheduleResult.recordset[0];
    const taskUserId = Number(schedule.userid);

    if (Number(req.user?.id) !== taskUserId) {
      return res.status(403).json({ message: 'You can only complete your own tasks.' });
    }

    if (Number(schedule.groupid) !== groupId) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const isMember = await isGroupMember(pool, groupId, taskUserId);

    if (!isMember) {
      return res.status(403).json({ message: 'Not a member of this group.' });
    }

    const existingResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, groupId)
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

    const coinsChange = 10;

    const insertResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, groupId)
      .input('startdatetime', sql.DateTime2, schedule.startdatetime)
      .input('completedby', sql.Int, taskUserId)
      .input('coinsChange', sql.Int, coinsChange)
      .query(`
        INSERT INTO dbo.[schedule_completions] (userid, groupid, startdatetime, completedby, completedat)
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.completedby, INSERTED.completedat
        VALUES (@userid, @groupid, @startdatetime, @completedby, SYSUTCDATETIME());

        UPDATE dbo.[users]
        SET coins = coins + @coinsChange
        WHERE id = @userid
      `);

    return res.json({ message: 'Congrats! 🎉🎊', completion: insertResult.recordset[0] });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/leaderboard', async (req, res) => {
  const groupId = Number(req.params.id);

  try {
    await ensureCompletionTable();
    const pool = await getPool();
    const isMember = await isGroupMember(pool, groupId, Number(req.user?.id));

    if (!isMember) {
      return res.status(403).json({ message: 'Not a member of this group.' });
    }

    const result = await pool
      .request()
      .input('groupid', sql.Int, groupId)
      .query(`
        SELECT u.id, u.name, u.email,
               COUNT(c.id) AS completedCount
        FROM dbo.[grouppart] gp
        INNER JOIN dbo.[users] u ON u.id = gp.userid
        LEFT JOIN dbo.[schedule_completions] c
          ON c.userid = gp.userid
         AND c.groupid = gp.groupid
        WHERE gp.groupid = @groupid
        GROUP BY u.id, u.name, u.email
        ORDER BY completedCount DESC, u.name ASC
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
      .query(`
        SELECT id, name, creatorid, [creation date] AS creationDate
        FROM dbo.[groups]
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { name, creatorid, creationDate } = req.body;

  if (!name || !creatorid) {
    return res.status(400).json({ message: 'name and creatorid are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .input('name', sql.NVarChar(255), name)
      .input('creatorid', sql.Int, Number(creatorid))
      .input('creationDate', sql.DateTime2, creationDate || null)
      .query(`
        UPDATE dbo.[groups]
        SET name = @name,
            creatorid = @creatorid,
            [creation date] = ISNULL(@creationDate, [creation date])
        OUTPUT INSERTED.id, INSERTED.name, INSERTED.creatorid, INSERTED.[creation date] AS creationDate
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'Group not found.' });
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
      .query('DELETE FROM dbo.[groups] WHERE id = @id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    return res.json({ message: 'Group deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
