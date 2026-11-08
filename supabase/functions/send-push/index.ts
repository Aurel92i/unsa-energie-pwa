// Envoi de notifications push, réservé aux admins/représentants connectés.
// Corps : { title, body, url?, user_ids? }  (sans user_ids = tous les abonnés)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendWebPush } from './webpush.js';

const VAPID_PUBLIC = 'BPVvfkZOxg9HUz98VjLwyovTN-7-vr4rfCU-oTOQlNI1PbhbZ1eZI2-VvTTZFfqQOQaHexI7tt7gfMF8OHgP71I';
const VAPID_SUBJECT = 'mailto:aurelien.herbin@grdf.fr';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);
  try {
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // 1) L'appelant doit être un admin connecté
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await sb.auth.getUser(token);
    if (!user) return json({ error: 'Non authentifié' }, 401);
    const { data: prof } = await sb.from('unsa_profiles').select('role').eq('id', user.id).single();
    if (!prof || !['admin', 'representant'].includes(prof.role)) return json({ error: 'Accès refusé' }, 403);

    // 2) Message
    const { title, body, url, user_ids } = await req.json();
    if (!title || typeof title !== 'string') return json({ error: 'Titre requis' }, 400);
    const payload = JSON.stringify({
      title: title.slice(0, 120),
      body: String(body ?? '').slice(0, 300),
      url: url || './',
      icon: './icons/icon-192x192.png',
    });

    // 3) Clé privée VAPID lue dans le coffre-fort Supabase (Vault)
    const { data: vapidPrivate, error: vErr } = await sb.rpc('unsa_vapid_private_key');
    if (vErr || !vapidPrivate) return json({ error: 'Clé VAPID introuvable' }, 500);
    const vapid = { publicKey: VAPID_PUBLIC, privateKey: vapidPrivate as string, subject: VAPID_SUBJECT };

    // 4) Abonnés
    let query = sb.from('unsa_push_subscriptions').select('id, subscription');
    if (Array.isArray(user_ids) && user_ids.length) query = query.in('user_id', user_ids);
    const { data: subs, error: sErr } = await query;
    if (sErr) return json({ error: sErr.message }, 500);

    // 5) Envoi par lots, suppression des abonnements expirés
    let sent = 0, failed = 0;
    const expired: string[] = [];
    const list = subs ?? [];
    for (let i = 0; i < list.length; i += 50) {
      const results = await Promise.allSettled(list.slice(i, i + 50).map(async (s) => {
        const status = await sendWebPush(s.subscription, payload, vapid);
        if (status === 404 || status === 410) expired.push(s.id);
        return status;
      }));
      for (const r of results) {
        if (r.status === 'fulfilled' && r.value >= 200 && r.value < 300) sent++; else failed++;
      }
    }
    if (expired.length) await sb.from('unsa_push_subscriptions').delete().in('id', expired);
    return json({ sent, failed, total: list.length, expired: expired.length });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
