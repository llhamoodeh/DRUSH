require('dotenv').config();
const express = require('express');
const cors = require('cors');

const authMiddleware = require('./middleware/auth');
const authRoutes = require('./routes/auth');
const groupsRoutes = require('./routes/groups');
const grouppartRoutes = require('./routes/grouppart');
const scheduleRoutes = require('./routes/schedule');
const massegesRoutes = require('./routes/masseges');
const notificationsRoutes = require('./routes/notifications');

const app = express();

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ ok: true });
});

app.use('/api/auth', authRoutes);
app.use('/api/groups', authMiddleware, groupsRoutes);
app.use('/api/grouppart', authMiddleware, grouppartRoutes);
app.use('/api/schedule', authMiddleware, scheduleRoutes);
app.use('/api/masseges', authMiddleware, massegesRoutes);
app.use('/api/notifications', authMiddleware, notificationsRoutes);

app.use((err, req, res, next) => {
  if (res.headersSent) {
    return next(err);
  }

  return res.status(500).json({ message: err.message || 'Internal server error.' });
});

module.exports = app;
