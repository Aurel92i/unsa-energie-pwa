-- Notifications push pour tous (visiteurs et adhérents), plusieurs appareils par personne
alter table public.unsa_push_subscriptions drop constraint if exists unsa_push_subscriptions_user_id_key;
alter table public.unsa_push_subscriptions add column if not exists endpoint text generated always as (subscription->>'endpoint') stored;
alter table public.unsa_push_subscriptions add column if not exists updated_at timestamptz default now();
delete from public.unsa_push_subscriptions a using public.unsa_push_subscriptions b
  where a.endpoint = b.endpoint and a.created_at < b.created_at;
create unique index if not exists unsa_push_subscriptions_endpoint_key on public.unsa_push_subscriptions(endpoint);

-- Plus aucun accès direct à la table : enregistrement via la fonction ci-dessous, lecture par les admins
drop policy if exists push_insert on public.unsa_push_subscriptions;
drop policy if exists push_select on public.unsa_push_subscriptions;
drop policy if exists push_update on public.unsa_push_subscriptions;
create policy push_admin_select on public.unsa_push_subscriptions for select using (public.unsa_is_admin());

create or replace function public.unsa_save_push_subscription(p_sub jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_endpoint text := p_sub->>'endpoint';
begin
  if v_endpoint is null or v_endpoint !~ '^https://' or length(v_endpoint) > 1000
     or p_sub->'keys'->>'p256dh' is null or p_sub->'keys'->>'auth' is null
     or length(p_sub::text) > 4000 then
    raise exception 'Abonnement invalide';
  end if;
  insert into unsa_push_subscriptions (user_id, subscription)
  values (auth.uid(), jsonb_build_object('endpoint', v_endpoint, 'keys', jsonb_build_object('p256dh', p_sub->'keys'->>'p256dh', 'auth', p_sub->'keys'->>'auth')))
  on conflict (endpoint) do update
    set subscription = excluded.subscription,
        user_id = coalesce(auth.uid(), unsa_push_subscriptions.user_id),
        updated_at = now();
end;
$$;
grant execute on function public.unsa_save_push_subscription(jsonb) to anon, authenticated;

-- Clé privée VAPID : stockée dans Supabase Vault (jamais dans le dépôt), lisible par le service uniquement.
-- Création (une seule fois, depuis l'éditeur SQL) :
--   select vault.create_secret('<clé privée VAPID>', 'unsa_vapid_private_key', 'Clé privée VAPID');
create or replace function public.unsa_vapid_private_key() returns text
language sql stable security definer set search_path = public, vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'unsa_vapid_private_key' limit 1;
$$;
revoke all on function public.unsa_vapid_private_key() from public, anon, authenticated;
grant execute on function public.unsa_vapid_private_key() to service_role;
