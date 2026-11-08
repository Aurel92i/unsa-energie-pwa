-- UNSA Énergies : espace adhérent, base adhérents, FAQ, durcissement des droits

-- ── Helpers ──
create or replace function public.unsa_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from unsa_profiles where id = auth.uid() and role in ('admin','representant'));
$$;

create or replace function public.unsa_is_adherent() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from unsa_profiles where id = auth.uid() and (adherent_verified or role in ('admin','representant')));
$$;

-- ── Base adhérents (lisible uniquement par les admins) ──
create table if not exists public.unsa_members (
  id uuid primary key default gen_random_uuid(),
  nom_complet text not null,
  college text,
  unite_irp text,
  fonction text,
  situation text,
  syndicat text,
  portable text,
  email text,
  email_norm text generated always as (lower(trim(email))) stored,
  created_at timestamptz not null default now()
);
create index if not exists unsa_members_email_norm_idx on public.unsa_members(email_norm);
alter table public.unsa_members enable row level security;
drop policy if exists members_admin_all on public.unsa_members;
create policy members_admin_all on public.unsa_members for all
  using (public.unsa_is_admin()) with check (public.unsa_is_admin());

-- Reconnaissance automatique : l'adhérent connecté (e-mail confirmé) dont l'e-mail
-- figure dans la base est marqué adhérent. Ne révèle jamais la liste.
create or replace function public.unsa_claim_membership() returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_email text;
  v_confirmed timestamptz;
  v_found boolean;
begin
  if auth.uid() is null then return false; end if;
  select lower(trim(email)), email_confirmed_at into v_email, v_confirmed from auth.users where id = auth.uid();
  select exists(select 1 from unsa_members where email_norm = v_email) into v_found;
  if v_found and v_confirmed is not null then
    perform set_config('unsa.claim', '1', true);
    update unsa_profiles set adherent_verified = true, is_adherent = true where id = auth.uid() and not adherent_verified;
  end if;
  return coalesce((select adherent_verified or role in ('admin','representant') from unsa_profiles where id = auth.uid()), false);
end;
$$;
revoke all on function public.unsa_claim_membership() from public, anon;
grant execute on function public.unsa_claim_membership() to authenticated;

-- ── FAQ (lecture publique, écriture admin) ──
create table if not exists public.unsa_faq (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  answer text not null,
  position int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.unsa_faq enable row level security;
drop policy if exists faq_select on public.unsa_faq;
drop policy if exists faq_admin_write on public.unsa_faq;
create policy faq_select on public.unsa_faq for select using (true);
create policy faq_admin_write on public.unsa_faq for all
  using (public.unsa_is_admin()) with check (public.unsa_is_admin());

-- ── Profils : chacun ne lit/modifie que le sien, les admins tout ──
drop policy if exists profiles_select on public.unsa_profiles;
drop policy if exists profiles_update_own on public.unsa_profiles;
create policy profiles_select on public.unsa_profiles for select
  using (auth.uid() = id or public.unsa_is_admin());
create policy profiles_update_own on public.unsa_profiles for update
  using (auth.uid() = id or public.unsa_is_admin());

-- Un utilisateur ne peut pas modifier lui-même son rôle ni son statut adhérent
create or replace function public.unsa_protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.unsa_is_admin() or coalesce(current_setting('unsa.claim', true), '') = '1' or auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.role := 'user'; new.adherent_verified := false; new.is_adherent := false;
  else
    new.role := old.role; new.adherent_verified := old.adherent_verified; new.is_adherent := old.is_adherent;
  end if;
  return new;
end;
$$;
drop trigger if exists unsa_protect_profile on public.unsa_profiles;
create trigger unsa_protect_profile before insert or update on public.unsa_profiles
  for each row execute function public.unsa_protect_profile();

-- ── Contenus : écriture réservée aux admins ──
drop policy if exists actus_insert_auth on public.unsa_actus;
drop policy if exists actus_delete_auth on public.unsa_actus;
drop policy if exists actus_update_admin on public.unsa_actus;
create policy actus_insert_auth on public.unsa_actus for insert with check (public.unsa_is_admin());
create policy actus_delete_auth on public.unsa_actus for delete using (public.unsa_is_admin());
create policy actus_update_admin on public.unsa_actus for update using (public.unsa_is_admin());

-- Documents et événements : lecture adhérents, écriture admins
drop policy if exists docs_select on public.unsa_documents;
drop policy if exists docs_insert on public.unsa_documents;
drop policy if exists docs_delete on public.unsa_documents;
create policy docs_select on public.unsa_documents for select using (public.unsa_is_adherent());
create policy docs_insert on public.unsa_documents for insert with check (public.unsa_is_admin());
create policy docs_delete on public.unsa_documents for delete using (public.unsa_is_admin());

drop policy if exists events_select on public.unsa_events;
drop policy if exists events_insert on public.unsa_events;
drop policy if exists events_update on public.unsa_events;
drop policy if exists events_delete on public.unsa_events;
create policy events_select on public.unsa_events for select using (public.unsa_is_adherent());
create policy events_insert on public.unsa_events for insert with check (public.unsa_is_admin());
create policy events_update on public.unsa_events for update using (public.unsa_is_admin());
create policy events_delete on public.unsa_events for delete using (public.unsa_is_admin());
