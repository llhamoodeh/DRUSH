const http = require('http');
const https = require('https');
const FormData = require('form-data');
const multer = require('multer');

const AI_PHOTO_URL = process.env.AI_PHOTO_URL || 'http://159.203.179.118:8000/analyze';
const AI_CHAT_URL = process.env.AI_CHAT_URL || 'http://159.203.179.118/chat';
const MAX_FILE_BYTES = Number(process.env.TASK_PHOTO_MAX_BYTES) || 8 * 1024 * 1024;

const completionUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    files: 2,
    fileSize: MAX_FILE_BYTES
  }
});

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

function postForm(url, form) {
  const parsed = new URL(url);
  const isHttps = parsed.protocol === 'https:';

  const options = {
    hostname: parsed.hostname,
    port: parsed.port || (isHttps ? 443 : 80),
    path: parsed.pathname + parsed.search,
    method: 'POST',
    headers: form.getHeaders()
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
    form.pipe(req);
  });
}

function parseJsonBody(body) {
  try {
    return JSON.parse(body || '{}');
  } catch (err) {
    return {};
  }
}

function getSingleFile(files, fieldName) {
  if (!files || !files[fieldName]) {
    return null;
  }

  const candidates = files[fieldName];
  if (!Array.isArray(candidates) || candidates.length === 0) {
    return null;
  }

  return candidates[0];
}

function validateImageFile(file, label) {
  if (!file) {
    return { ok: false, status: 400, message: `${label} photo is required.` };
  }

  if (!file.buffer || file.buffer.length === 0) {
    return { ok: false, status: 400, message: `${label} photo is empty.` };
  }

  if (!file.mimetype || !file.mimetype.startsWith('image/')) {
    return { ok: false, status: 400, message: `${label} photo must be an image.` };
  }

  return { ok: true };
}

async function analyzePhoto(file, label) {
  const form = new FormData();
  const filename = file.originalname || `${label.toLowerCase()}-photo`;
  const contentType = file.mimetype || 'application/octet-stream';

  form.append('file', file.buffer, { filename, contentType });

  const response = await postForm(AI_PHOTO_URL, form);
  if (response.status !== 200) {
    throw new Error('Photo analysis service returned an error.');
  }

  const parsed = parseJsonBody(response.body);
  const caption = typeof parsed.caption === 'string' ? parsed.caption.trim() : '';

  if (!caption) {
    throw new Error('Photo analysis service returned an empty caption.');
  }

  return caption;
}

function buildValidationPrompt({ taskDescription, beforeCaption, afterCaption }) {
  const description = (taskDescription || '').trim() || 'No task description provided.';

  return [
    'You validate whether a task was completed based on before and after photos.',
    'Compare the task description with the two captions.',
    'If the task looks at least 50% completed and you are confident, reply with exactly: tes',
    'If you are unsure or completion is below 50%, reply with: no',
    '',
    `Task description: ${description}`,
    `Before photo caption: ${beforeCaption}`,
    `After photo caption: ${afterCaption}`
  ].join('\n');
}

async function validateTaskCompletion({ taskDescription, beforePhoto, afterPhoto }) {
  const beforeCheck = validateImageFile(beforePhoto, 'Before');
  if (!beforeCheck.ok) {
    return beforeCheck;
  }

  const afterCheck = validateImageFile(afterPhoto, 'After');
  if (!afterCheck.ok) {
    return afterCheck;
  }

  let beforeCaption;
  let afterCaption;

  try {
    [beforeCaption, afterCaption] = await Promise.all([
      analyzePhoto(beforePhoto, 'Before'),
      analyzePhoto(afterPhoto, 'After')
    ]);
  } catch (err) {
    return {
      ok: false,
      status: 502,
      message: err.message || 'Failed to analyze task photos.'
    };
  }

  const message = buildValidationPrompt({ taskDescription, beforeCaption, afterCaption });
  const aiResponse = await postJson(AI_CHAT_URL, { message });

  if (aiResponse.status !== 200) {
    return {
      ok: false,
      status: 502,
      message: 'AI validation service returned an error.'
    };
  }

  const parsed = parseJsonBody(aiResponse.body);
  const reply = typeof parsed.reply === 'string' ? parsed.reply.trim() : '';
  const passed = reply.toLowerCase() === 'tes';

  if (!passed) {
    return {
      ok: false,
      status: 400,
      message: 'Task completion could not be verified.'
    };
  }

  return {
    ok: true,
    captions: { before: beforeCaption, after: afterCaption },
    reply
  };
}

module.exports = {
  completionUpload,
  getSingleFile,
  validateTaskCompletion
};
