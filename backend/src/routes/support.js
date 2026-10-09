import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail } from '../http.js';
import { cleanMultiline } from '../text_safety.js';

export const router = Router();
router.use(requireAuth);

export const SUPPORT_CATEGORIES = ['Aile', 'ACM ve Yayıncı Konuları', 'Oyunlar', 'Etkinlikler', 'Onaylamalar', 'Özelden yapılan küfür ve hakaret', 'VIP', 'BCM', 'Diğer'];

const msg = (m) => ({ id: m.id, fromStaff: m.from_staff, category: m.category, text: m.body, createdAt: m.created_at });

// Kendi müşteri hizmetleri yazışmam (son 200). Okunmamış destek yanıtları okundu olur.
router.get('/messages', async (req, res) => {
  const r = await query(`SELECT * FROM support_messages WHERE user_id = $1 ORDER BY created_at DESC LIMIT 200`, [req.user.id]);
  await query(`UPDATE support_messages SET read_at = NOW() WHERE user_id = $1 AND from_staff = TRUE AND read_at IS NULL`, [req.user.id]);
  res.json({ messages: r.rows.reverse().map(msg) });
});

router.get('/unread', async (req, res) => {
  const r = await query(`SELECT COUNT(*)::int AS n FROM support_messages WHERE user_id = $1 AND from_staff = TRUE AND read_at IS NULL`, [req.user.id]);
  res.json({ unread: r.rows[0].n });
});

router.post('/messages', userLimit('support10s', 5, 10e3), userLimit('support1h', 60, 3600e3), async (req, res) => {
  const body = cleanMultiline(req.body?.text, 1500);
  if (!body) throw fail('Mesaj boş olamaz.');
  const category = SUPPORT_CATEGORIES.includes(req.body?.category) ? req.body.category : null;
  const m = (await query(`INSERT INTO support_messages(user_id, category, body) VALUES($1,$2,$3) RETURNING *`, [req.user.id, category, body])).rows[0];
  res.status(201).json({ message: msg(m) });
});
