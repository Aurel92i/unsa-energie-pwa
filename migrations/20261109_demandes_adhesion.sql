-- Demandes d'adhésion déposées depuis le site, validées ou déclinées dans l'admin
create table if not exists public.unsa_adhesion_requests (
  id uuid primary key default gen_random_uuid(),
  prenom text not null,
  nom text not null,
  email text not null,
  telephone text,
  formule text,
  statut_pro text,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid,
  -- Adresses acceptées : @grdf.fr, @unsa.fr (et @test.fr pour les essais)
  constraint adh_email_domain check (lower(trim(email)) ~ '^[^@\s]+@(grdf|unsa|test)\.fr$'),
  constraint adh_lengths check (
    char_length(prenom) between 1 and 100 and char_length(nom) between 1 and 100
    and char_length(email) <= 200 and coalesce(char_length(telephone),0) <= 30
    and coalesce(char_length(formule),0) <= 100 and coalesce(char_length(statut_pro),0) <= 100)
);
alter table public.unsa_adhesion_requests enable row level security;
drop policy if exists adhreq_insert on public.unsa_adhesion_requests;
drop policy if exists adhreq_admin on public.unsa_adhesion_requests;
create policy adhreq_insert on public.unsa_adhesion_requests for insert to anon, authenticated
  with check (status = 'pending' and processed_at is null and processed_by is null);
create policy adhreq_admin on public.unsa_adhesion_requests for all
  using (public.unsa_is_admin()) with check (public.unsa_is_admin());

-- Validation / refus (admin) : une demande validée ajoute la personne à la base adhérents
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
  if p_approve and not exists (select 1 from unsa_members where email_norm = lower(trim(r.email))) then
    insert into unsa_members (nom_complet, situation, portable, email, fonction)
    values (upper(r.nom) || ' ' || r.prenom, 'Adhérent', r.telephone, lower(trim(r.email)), r.statut_pro);
  end if;
end;
$$;
revoke all on function public.unsa_process_adhesion(uuid, boolean) from public, anon;
grant execute on function public.unsa_process_adhesion(uuid, boolean) to authenticated;
