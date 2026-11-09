-- UNSA Énergies : régions (contacts + équipes), comptes validés par l'admin, contenus d'exemple

-- ── Régions : e-mail de contact et équipe, modifiables dans l'admin ──
create table if not exists public.unsa_regions (
  name text primary key,
  email text,
  team text,          -- une ligne par personne : « Prénom NOM — Rôle »
  sort int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.unsa_regions enable row level security;
drop policy if exists regions_select on public.unsa_regions;
drop policy if exists regions_admin on public.unsa_regions;
create policy regions_select on public.unsa_regions for select using (true);
create policy regions_admin on public.unsa_regions for all using (public.unsa_is_admin()) with check (public.unsa_is_admin());

-- ── Actualités d'exemple (suppression groupée possible depuis l'admin) ──
alter table public.unsa_actus add column if not exists demo boolean not null default false;

-- ── Demandes : adhésion (formulaire « Adhérer ») ou création de compte ──
alter table public.unsa_adhesion_requests add column if not exists kind text not null default 'adhesion';
alter table public.unsa_adhesion_requests drop constraint if exists adh_kind;
alter table public.unsa_adhesion_requests add constraint adh_kind check (kind in ('adhesion','compte'));
alter table public.unsa_adhesion_requests add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.unsa_adhesion_requests drop constraint if exists adh_email_domain;
alter table public.unsa_adhesion_requests add constraint adh_email_domain
  check (kind = 'compte' or lower(trim(email)) ~ '^[^@\s]+@(grdf|unsa|test)\.fr$');
-- Les visiteurs ne peuvent déposer que des demandes d'adhésion ; les demandes de compte
-- sont créées par la fonction serveur create-account.
drop policy if exists adhreq_insert on public.unsa_adhesion_requests;
create policy adhreq_insert on public.unsa_adhesion_requests for insert to anon, authenticated
  with check (status = 'pending' and processed_at is null and processed_by is null and kind = 'adhesion' and user_id is null);

-- ── Statut d'un compte : plus de reconnaissance automatique, l'admin valide ──
create or replace function public.unsa_member_status() returns text
language plpgsql stable security definer set search_path = public as $$
declare v_adh boolean; v_req text;
begin
  if auth.uid() is null then return 'none'; end if;
  select adherent_verified or role in ('admin','representant') into v_adh from unsa_profiles where id = auth.uid();
  if coalesce(v_adh, false) then return 'adherent'; end if;
  select status into v_req from unsa_adhesion_requests where user_id = auth.uid() and kind = 'compte' order by created_at desc limit 1;
  return case v_req when 'pending' then 'pending' when 'declined' then 'declined' else 'none' end;
end;
$$;
revoke all on function public.unsa_member_status() from public, anon;
grant execute on function public.unsa_member_status() to authenticated;

-- L'ancienne reconnaissance automatique ne donne plus aucun accès (compatibilité)
drop function if exists public.unsa_claim_membership();
create function public.unsa_claim_membership() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select adherent_verified or role in ('admin','representant') from unsa_profiles where id = auth.uid()), false);
$$;
revoke all on function public.unsa_claim_membership() from public, anon;
grant execute on function public.unsa_claim_membership() to authenticated;

-- ── Traitement d'une demande (admin) ──
create or replace function public.unsa_process_adhesion(p_id uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r unsa_adhesion_requests;
begin
  if not public.unsa_is_admin() then raise exception 'Accès refusé'; end if;
  update unsa_adhesion_requests
     set status = case when p_approve then 'approved' else 'declined' end,
         processed_at = now(), processed_by = auth.uid()
   where id = p_id and status = 'pending'
  returning * into r;
  if not found then raise exception 'Demande introuvable ou déjà traitée'; end if;
  if r.kind = 'compte' then
    if p_approve then
      update unsa_profiles set adherent_verified = true, is_adherent = true where id = r.user_id;
    end if;
  elsif p_approve and not exists (select 1 from unsa_members where email_norm = lower(trim(r.email))) then
    insert into unsa_members (nom_complet, situation, portable, email, fonction)
    values (upper(r.nom) || ' ' || r.prenom, 'Adhérent', r.telephone, lower(trim(r.email)), r.statut_pro);
  end if;
end;
$$;

-- ── Désactivation des notifications depuis le site (bouton cloche) ──
create or replace function public.unsa_delete_push_subscription(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from unsa_push_subscriptions where endpoint = p_endpoint;
$$;
grant execute on function public.unsa_delete_push_subscription(text) to anon, authenticated;

-- La région d'un profil vient désormais de la géolocalisation ou du choix de l'utilisateur
alter table public.unsa_profiles alter column agence drop default;
