-- SASHA Commerce — Phase 1 Foundation
-- Multi-tenant core: profiles, stores, members, plans, feature flags, API versions, audit log.
-- Run in Supabase SQL Editor (or `supabase db push`).

create extension if not exists pgcrypto;

-- ---------- Types ----------
do $$ begin
  create type public.store_role as enum ('owner', 'admin', 'staff');
exception when duplicate_object then null; end $$;

-- ---------- Tables ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  is_super_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.plans (
  id text primary key,
  name text not null,
  price_cents integer not null default 0,
  limits jsonb not null default '{}'::jsonb
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 2 and 80),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$'),
  plan_id text not null default 'free' references public.plans(id),
  currency char(3) not null default 'USD',
  locale text not null default 'en',
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.store_members (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.store_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);
create index on public.store_members (user_id);

create table public.feature_flags (
  key text primary key,
  description text,
  stage text not null default 'stable' check (stage in ('stable','beta','preview')),
  default_enabled boolean not null default false
);

create table public.plan_features (
  plan_id text not null references public.plans(id) on delete cascade,
  flag_key text not null references public.feature_flags(key) on delete cascade,
  enabled boolean not null default true,
  primary key (plan_id, flag_key)
);

create table public.store_feature_overrides (
  store_id uuid not null references public.stores(id) on delete cascade,
  flag_key text not null references public.feature_flags(key) on delete cascade,
  enabled boolean not null,
  primary key (store_id, flag_key)
);

create table public.api_versions (
  version text primary key,
  status text not null check (status in ('stable','beta','preview','deprecated','sunset')),
  released_at date,
  sunset_at date
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  store_id uuid references public.stores(id) on delete set null,
  actor_id uuid,
  action text not null,
  entity text,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.audit_log (store_id, created_at desc);

-- Append-only audit log
create or replace function public.audit_log_immutable() returns trigger
language plpgsql as $$ begin raise exception 'audit_log is append-only'; end $$;
create trigger audit_log_no_update before update or delete on public.audit_log
  for each row execute function public.audit_log_immutable();

-- ---------- Helper functions (SECURITY DEFINER avoids RLS recursion) ----------
create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_super_admin from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.is_store_member(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.store_members where store_id = sid and user_id = auth.uid())
$$;

create or replace function public.has_store_role(sid uuid, roles public.store_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.store_members
                 where store_id = sid and user_id = auth.uid() and role = any(roles))
$$;

-- PLAN -> ENTITLEMENTS -> FEATURES: override > plan > default
create or replace function public.store_feature_enabled(p_store uuid, p_flag text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v boolean;
begin
  if not (public.is_store_member(p_store) or public.is_super_admin()) then return false; end if;
  select enabled into v from public.store_feature_overrides where store_id = p_store and flag_key = p_flag;
  if found then return v; end if;
  select pf.enabled into v from public.plan_features pf
    join public.stores s on s.plan_id = pf.plan_id
    where s.id = p_store and pf.flag_key = p_flag;
  if found then return v; end if;
  select default_enabled into v from public.feature_flags where key = p_flag;
  return coalesce(v, false);
end $$;

-- Create a store + make caller the owner (only way clients create stores)
create or replace function public.create_store(p_name text, p_slug text) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid; owned int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select count(*) into owned from public.stores where created_by = auth.uid();
  if owned >= 5 and not public.is_super_admin() then raise exception 'store limit reached (5)'; end if;
  insert into public.stores (name, slug, created_by) values (trim(p_name), lower(trim(p_slug)), auth.uid())
    returning id into sid;
  insert into public.store_members (store_id, user_id, role) values (sid, auth.uid(), 'owner');
  insert into public.audit_log (store_id, actor_id, action, entity, entity_id)
    values (sid, auth.uid(), 'store.created', 'store', sid::text);
  return sid;
end $$;

-- Profile auto-creation on signup
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data->>'full_name');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.plans enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.feature_flags enable row level security;
alter table public.plan_features enable row level security;
alter table public.store_feature_overrides enable row level security;
alter table public.api_versions enable row level security;
alter table public.audit_log enable row level security;

create policy profiles_select on public.profiles for select using (id = auth.uid() or public.is_super_admin());
create policy profiles_update on public.profiles for update using (id = auth.uid());

create policy plans_read on public.plans for select using (true);
create policy flags_read on public.feature_flags for select using (true);
create policy plan_features_read on public.plan_features for select using (true);
create policy api_versions_read on public.api_versions for select using (true);

create policy stores_select on public.stores for select
  using (public.is_store_member(id) or public.is_super_admin());
create policy stores_update on public.stores for update
  using (public.has_store_role(id, array['owner','admin']::public.store_role[]));

create policy members_select on public.store_members for select
  using (public.is_store_member(store_id) or public.is_super_admin());

create policy overrides_select on public.store_feature_overrides for select
  using (public.is_store_member(store_id) or public.is_super_admin());

create policy audit_select on public.audit_log for select
  using (public.has_store_role(store_id, array['owner','admin']::public.store_role[]) or public.is_super_admin());

-- Privilege hardening: clients can never change plan, status, or super-admin flag
revoke all on public.profiles, public.stores, public.store_members, public.audit_log,
  public.plans, public.feature_flags, public.plan_features, public.store_feature_overrides,
  public.api_versions from anon, authenticated;
grant select on public.profiles, public.stores, public.store_members, public.audit_log,
  public.plans, public.feature_flags, public.plan_features, public.store_feature_overrides,
  public.api_versions to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant update (name, currency, locale) on public.stores to authenticated;
grant execute on function public.create_store(text, text) to authenticated;
grant execute on function public.store_feature_enabled(uuid, text) to authenticated;

-- ---------- Seed data ----------
insert into public.plans (id, name, price_cents, limits) values
  ('free',       'Free',       0,     '{"products":50,"staff":1,"api_rpm":60}'),
  ('basic',      'Basic',      2900,  '{"products":1000,"staff":5,"api_rpm":300}'),
  ('pro',        'Pro',        7900,  '{"products":50000,"staff":15,"api_rpm":1200}'),
  ('enterprise', 'Enterprise', 29900, '{"products":-1,"staff":-1,"api_rpm":6000}');

insert into public.feature_flags (key, description, stage, default_enabled) values
  ('catalog',          'Products and collections',        'stable', true),
  ('markets',          'Multi-market selling',            'stable', false),
  ('b2b',              'B2B companies and price lists',   'beta',   false),
  ('functions',        'Custom commerce Functions',       'preview',false),
  ('ai_agents',        'SASHA AI agents',                 'beta',   false),
  ('pos',              'Point of sale',                   'stable', false),
  ('graphql_api',      'GraphQL Admin API',               'stable', false);

insert into public.plan_features (plan_id, flag_key, enabled) values
  ('basic','markets',true),
  ('pro','markets',true),('pro','b2b',true),('pro','pos',true),('pro','graphql_api',true),
  ('enterprise','markets',true),('enterprise','b2b',true),('enterprise','pos',true),
  ('enterprise','graphql_api',true),('enterprise','functions',true),('enterprise','ai_agents',true);

insert into public.api_versions (version, status, released_at) values
  ('2026-01','stable','2026-01-01'),
  ('2026-04','stable','2026-04-01'),
  ('2026-07','beta','2026-07-01');

-- To make yourself super admin, run once (replace email):
-- update public.profiles set is_super_admin = true where email = 'you@example.com';
