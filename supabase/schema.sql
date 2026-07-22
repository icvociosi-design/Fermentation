-- Schéma Supabase pour "Suivi de fermentation".
--
-- À exécuter une seule fois dans le SQL Editor du dashboard Supabase du projet
-- (https://supabase.com/dashboard/project/gctvtjelleajwpcbkqqs/sql/new).
--
-- ATTENTION : ce script commence par supprimer les tables existantes du même nom.
-- Elles proviennent d'une version précédente de l'application (non fonctionnelle,
-- bloquée par une policy RLS récursive) et ne contiennent aucune donnée exploitable.
-- Si vous avez des données à conserver dans ces tables, ne lancez pas ce script
-- sans les exporter au préalable.

drop table if exists mesures cascade;
drop table if exists cuves cascade;
drop table if exists alertes_globales cascade;
drop table if exists levures cascade;
drop table if exists variables_calculees cascade;
drop table if exists profiles cascade;
drop table if exists organisations cascade;

-- ─── Tables ───────────────────────────────────────────────────────────────────

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table cuves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nom text not null,
  appellation text default '',
  couleur text default '',
  qualite text default '',
  tap numeric,
  azote_assimilable numeric,
  levure text default '',
  archived boolean not null default false,
  date_archive date,
  alertes_validees text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table mesures (
  id uuid primary key default gen_random_uuid(),
  cuve_id uuid not null references cuves(id) on delete cascade,
  date date not null,
  densite numeric not null,
  temperature numeric not null,
  unique (cuve_id, date)
);

-- Configuration partagée entre tous les comptes (alertes, levures, variables calculées)
create table alertes_globales (
  id bigint primary key generated always as identity,
  nom text not null,
  jonctions jsonb not null default '[]',
  conditions jsonb not null default '[]',
  severity text not null,
  message text not null,
  reactivable boolean not null default true
);

create table levures (
  id bigint primary key generated always as identity,
  nom text not null,
  besoin_azote text not null
);

create table variables_calculees (
  id bigint primary key generated always as identity,
  nom text not null,
  formule text not null,
  unite text not null default '',
  visible boolean not null default true,
  ordre int not null default 0
);

-- ─── Profil auto-créé à l'inscription ────────────────────────────────────────
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists handle_new_user();

create function handle_new_user() returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ─── Row Level Security ───────────────────────────────────────────────────────
alter table profiles enable row level security;
alter table cuves enable row level security;
alter table mesures enable row level security;
alter table alertes_globales enable row level security;
alter table levures enable row level security;
alter table variables_calculees enable row level security;

-- Profils : chacun voit/modifie uniquement le sien (comparaison directe sur auth.uid(),
-- jamais de sous-requête sur profiles elle-même, pour éviter toute récursion RLS).
create policy "profiles self select" on profiles for select using (auth.uid() = id);
create policy "profiles self update" on profiles for update using (auth.uid() = id);
-- La policy ci-dessus autorise la ligne, mais pas la colonne : sans cette restriction,
-- un utilisateur pourrait s'auto-promouvoir admin via un simple PATCH sur son profil.
-- On retire le droit UPDATE générique et on ne le redonne que sur display_name.
revoke update on profiles from authenticated;
grant update (display_name) on profiles to authenticated;

-- Cuves / mesures : strictement privées à leur propriétaire.
create policy "cuves owner" on cuves for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "mesures owner" on mesures for all
  using (exists (select 1 from cuves where cuves.id = mesures.cuve_id and cuves.user_id = auth.uid()))
  with check (exists (select 1 from cuves where cuves.id = mesures.cuve_id and cuves.user_id = auth.uid()));

-- Configuration partagée : lecture pour tout utilisateur connecté, écriture réservée aux admins.
create policy "alertes read" on alertes_globales for select using (auth.uid() is not null);
create policy "alertes admin write" on alertes_globales for all
  using ((select is_admin from profiles where id = auth.uid()) = true)
  with check ((select is_admin from profiles where id = auth.uid()) = true);

create policy "levures read" on levures for select using (auth.uid() is not null);
create policy "levures admin write" on levures for all
  using ((select is_admin from profiles where id = auth.uid()) = true)
  with check ((select is_admin from profiles where id = auth.uid()) = true);

create policy "variables read" on variables_calculees for select using (auth.uid() is not null);
create policy "variables admin write" on variables_calculees for all
  using ((select is_admin from profiles where id = auth.uid()) = true)
  with check ((select is_admin from profiles where id = auth.uid()) = true);

-- ─── Étape manuelle après exécution ───────────────────────────────────────────
-- 1. Créez votre compte depuis l'application (email + mot de passe).
-- 2. Dans le Table Editor Supabase, table "profiles", passez votre ligne à
--    is_admin = true pour retrouver l'accès au panneau ⚙ Paramètres.
