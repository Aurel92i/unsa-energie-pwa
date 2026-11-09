// Création d'un compte « Espace adhérent » sans e-mail de confirmation.
// Le compte est créé désactivé : une demande « compte » apparaît dans l'admin,
// qui vérifie que la personne est bien adhérente avant de valider l'accès.
// Corps : { prenom, nom, email, password, telephone?, metier?, region?, website? (piège anti-robot) }
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
const clean = (v: unknown, max: number) => String(v ?? '').trim().slice(0, max);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);
  try {
    const b = await req.json();
    if (b.website) return json({ ok: true }); // robot : on ne crée rien
    const prenom = clean(b.prenom, 100), nom = clean(b.nom, 100);
    const email = clean(b.email, 200).toLowerCase();
    const password = String(b.password ?? '');
    const telephone = clean(b.telephone, 30), metier = clean(b.metier, 100), region = clean(b.region, 60);

    if (!prenom || !nom) return json({ error: 'Prénom et nom sont obligatoires.' }, 400);
    if (!/^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(email)) return json({ error: 'Adresse e-mail invalide.' }, 400);
    if (password.length < 8) return json({ error: 'Le mot de passe doit contenir au moins 8 caractères.' }, 400);

    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Compte créé directement « confirmé » : aucun e-mail n'est envoyé
    const { data, error } = await sb.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { prenom, nom, telephone, metier },
    });
    if (error) {
      const exists = /already|registered|exists/i.test(error.message);
      return json({ error: exists ? 'Un compte existe déjà avec cette adresse e-mail. Connectez-vous.' : error.message }, exists ? 409 : 400);
    }
    const userId = data.user!.id;

    // Profil (créé par le trigger handle_new_user) : compléter la région
    if (region) await sb.from('unsa_profiles').update({ agence: region }).eq('id', userId);

    // Demande à valider par l'admin
    const { error: rErr } = await sb.from('unsa_adhesion_requests').insert({
      kind: 'compte', user_id: userId, prenom, nom, email,
      telephone: telephone || null, statut_pro: metier || null, formule: region || null,
    });
    if (rErr) {
      await sb.auth.admin.deleteUser(userId);
      return json({ error: 'Impossible d\'enregistrer la demande. Réessayez plus tard.' }, 500);
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
