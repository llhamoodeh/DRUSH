const express = require('express');
const { sql, getPool } = require('../config/db');
const http = require('http');
const https = require('https');

const router = express.Router();

const AI_CHAT_URL = process.env.AI_CHAT_URL || 'http://159.203.179.118/chat';

let ensureTablePromise;

function postJson(url, payload) {
  const parsed = new URL(url);
  const body = JSON.stringify(payload);
  const isHttps = parsed.protocol === 'https:';

  const options = {
    hostname: parsed.hostname,
    port: parsed.port || (isHttps ? 443 : 80),
    path: parsed.pathname + parsed.search,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body)
    }
  };

  const transport = isHttps ? https : http;

  return new Promise((resolve, reject) => {
    const req = transport.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        resolve({ status: res.statusCode || 500, body: data });
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function ensureChatTable() {
  if (!ensureTablePromise) {
    const pool = await getPool();
    ensureTablePromise = pool.request().query(`
      IF OBJECT_ID('dbo.chat_messages', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[chat_messages] (
          id INT IDENTITY(1,1) PRIMARY KEY,
          userid INT NOT NULL,
          role NVARCHAR(20) NOT NULL,
          message NVARCHAR(MAX) NOT NULL,
          createdat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        )
      END
    `);
  }

  await ensureTablePromise;
}

async function fetchMessages({ userId, limit }) {
  const pool = await getPool();
  const request = pool.request().input('userid', sql.Int, userId);

  if (limit && Number.isFinite(limit)) {
    const result = await request
      .input('limit', sql.Int, limit)
      .query(`
        SELECT TOP (@limit) id, userid, role, message, createdat
        FROM dbo.[chat_messages]
        WHERE userid = @userid
        ORDER BY id DESC
      `);

    return result.recordset.reverse();
  }

  const result = await request.query(`
    SELECT id, userid, role, message, createdat
    FROM dbo.[chat_messages]
    WHERE userid = @userid
    ORDER BY id ASC
  `);

  return result.recordset;
}

async function insertMessage({ userId, role, message }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('userid', sql.Int, userId)
    .input('role', sql.NVarChar(20), role)
    .input('message', sql.NVarChar(sql.MAX), message)
    .query(`
      INSERT INTO dbo.[chat_messages] (userid, role, message, createdat)
      OUTPUT INSERTED.id, INSERTED.userid, INSERTED.role, INSERTED.message, INSERTED.createdat
      VALUES (@userid, @role, @message, SYSUTCDATETIME())
    `);

  return result.recordset[0];
}

function buildContext(messages, latestUserMessage) {
  const contextLines = messages
    .map((item) => {
      const prefix = item.role === 'user' ? 'User' : 'Assistant';
      return `${prefix}: ${item.message}`;
    })
    .join('\n');
  return [
    'Your name is SHAKIRA. You are a helpful, friendly assistant. You may discuss dopamine, reward, motivation, and related wellbeing topics when relevant.',
    'Provide informative, balanced answers and avoid giving medical diagnoses or instructions for illegal or unsafe activities.',
    '',
    'CONTEXT:',
    contextLines,
    '',
    'MESSAGE THAT SHOULD REPLY TO:',
    latestUserMessage
  ].join('\n');
}

function isDopamineRelated(text) {
  const lowered = text.toLowerCase();
  const keywords = [
    'dopamine',
    'reward',
    'motivation',
    'neurotransmitter',
    'addiction',
    'craving',
    'habit',
    'pleasure',
    'reinforcement',
    'incentive',
    'salience',
    'reward prediction'
  ];

  return keywords.some((keyword) => lowered.includes(keyword));
}

router.get('/', async (req, res) => {
  try {
    await ensureChatTable();
    const userId = Number(req.user?.id);
    const limit = req.query.limit ? Number(req.query.limit) : 60;
    const messages = await fetchMessages({ userId, limit });
    return res.json(messages);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const rawMessage = req.body?.message;
  const message = typeof rawMessage === 'string' ? rawMessage.trim() : '';

  if (!message) {
    return res.status(400).json({ message: 'message is required.' });
  }

  try {
    await ensureChatTable();
    const userId = Number(req.user?.id);

    await insertMessage({ userId, role: 'user', message });


    const contextMessages = await fetchMessages({ userId });
    const context = buildContext(contextMessages, message);

    const aiResponse = await postJson(AI_CHAT_URL, { message: context });
    if (aiResponse.status !== 200) {
      return res.status(502).json({ message: 'AI endpoint returned an error.' });
    }

    let reply = '';
    try {
      const parsed = JSON.parse(aiResponse.body || '{}');
      reply = typeof parsed.reply === 'string' ? parsed.reply : '';
    } catch (err) {
      reply = '';
    }

    if (!reply) {
      return res.status(502).json({ message: 'AI endpoint returned an empty reply.' });
    }

    await insertMessage({ userId, role: 'assistant', message: reply });

    const messages = await fetchMessages({ userId, limit: 200 });
    return res.json({ reply, messages });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/', async (req, res) => {
  try {
    await ensureChatTable();
    const userId = Number(req.user?.id);
    const pool = await getPool();
    await pool
      .request()
      .input('userid', sql.Int, userId)
      .query('DELETE FROM dbo.[chat_messages] WHERE userid = @userid');

    return res.json({ message: 'chat cleared.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isFinite(id)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureChatTable();
    const userId = Number(req.user?.id);
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, id)
      .input('userid', sql.Int, userId)
      .query('DELETE FROM dbo.[chat_messages] WHERE id = @id AND userid = @userid');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'message not found.' });
    }

    return res.json({ message: 'message deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
