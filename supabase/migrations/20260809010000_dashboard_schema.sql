-- Investor dashboard schema (app.roqhome.com).
--
-- Separate from the marketing-site tables (property_fingerprint_reports,
-- market_ready_requests, etc.), which stay service-role-only. Everything
-- here is read through the Supabase client from the dashboard app under
-- RLS, scoped per investor via investor_markets.
--
-- This project also hosts the flagship homeowner app (homes, pebbles,
-- rocks, milestones, vault_docs, ...), which already owns a `profiles`
-- table keyed to auth.users with its own unrelated shape (first_name,
-- plan, ai_messages_used, ...). The investor dashboard gets its own
-- `investor_profiles` table instead of colliding with it, and does NOT
-- attach a trigger to auth.users -- that table is shared with the
-- homeowner app's public sign-up flow, so a blanket "insert a row
-- whenever anyone signs up" trigger would fire for homeowner signups
-- too. Investor accounts are invite-only and admin-created, so the admin
-- inserts the matching investor_profiles + investor_markets rows by hand
-- (see the comment at the bottom of this file).
--
-- Market-level content (markets, submarkets, market_events, market_metrics,
-- competitors) is written by admins only -- via the Supabase Studio table
-- editor or the service role, never by the authenticated client -- so those
-- tables get SELECT policies only. `properties` is the one investor-owned
-- table and gets full CRUD scoped to the owning investor.

create table investor_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role text not null default 'investor' check (role in ('investor', 'admin')),
  created_at timestamptz not null default now()
);

create function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from investor_profiles where id = auth.uid() and role = 'admin'
  );
$$;

create table markets (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  state text not null,
  center_lat double precision not null,
  center_lng double precision not null,
  default_zoom numeric not null default 11,
  created_at timestamptz not null default now()
);

create table investor_markets (
  investor_id uuid not null references investor_profiles (id) on delete cascade,
  market_id uuid not null references markets (id) on delete cascade,
  granted_at timestamptz not null default now(),
  primary key (investor_id, market_id)
);

create function public.has_market_access(target_market_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from investor_markets im
    where im.investor_id = auth.uid() and im.market_id = target_market_id
  );
$$;

create table submarkets (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  name text not null,
  momentum text not null check (momentum in ('high', 'emerging', 'stable', 'watch')),
  median_price numeric,
  cash_on_cash_pct numeric,
  summary text,
  boundary jsonb, -- geojson polygon; nullable until we have drawn boundaries
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table market_events (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  type text not null check (type in ('development', 'permit', 'infrastructure', 'risk')),
  title text not null,
  description text,
  status text,
  lat double precision,
  lng double precision,
  source_url text,
  event_date date,
  created_at timestamptz not null default now()
);

create table market_metrics (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  period date not null, -- first of the month/quarter this snapshot represents
  population_growth_pct numeric,
  median_income numeric,
  job_growth_pct numeric,
  permit_activity_index numeric,
  price_momentum_index numeric,
  days_on_market int,
  inventory_index numeric,
  notes text,
  created_at timestamptz not null default now(),
  unique (market_id, period)
);

create table competitors (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  entity_name text not null,
  property_address text,
  purchase_date date,
  purchase_price numeric,
  strategy_notes text,
  source_url text,
  created_at timestamptz not null default now()
);

-- Off-market seller leads, bulk-sourced from county assessor/recorder
-- records (the "ROQ Outlook" lead package format already delivered to
-- Joel for Davenport/52804: long-tenure and absentee/out-of-state owners,
-- ranked by assessed value). Admin-imported per market; investors browse
-- and filter, they don't edit these rows.
create table leads (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  address text not null,
  zip text,
  owner_name text not null,
  owner_mailing_city text,
  owner_mailing_state text,
  is_absentee boolean not null default false,
  years_owned int, -- null when unknown; source caps at 20+, see years_owned_display
  years_owned_display text, -- preserves source formatting like "20+"
  assessed_value numeric,
  source text not null default 'county_assessor',
  captured_at date not null default current_date,
  created_at timestamptz not null default now()
);

create table properties (
  id uuid primary key default gen_random_uuid(),
  investor_id uuid not null references investor_profiles (id) on delete cascade,
  market_id uuid references markets (id) on delete set null,
  status text not null default 'target' check (status in ('owned', 'target', 'watchlist')),
  address text not null,
  price numeric,
  notes text,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table investor_profiles enable row level security;
alter table markets enable row level security;
alter table investor_markets enable row level security;
alter table submarkets enable row level security;
alter table market_events enable row level security;
alter table market_metrics enable row level security;
alter table competitors enable row level security;
alter table leads enable row level security;
alter table properties enable row level security;

create policy "investor_profiles_select_own_or_admin" on investor_profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "investor_profiles_update_own" on investor_profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy "markets_select_with_access" on markets
  for select using (public.has_market_access(id));

create policy "investor_markets_select_own_or_admin" on investor_markets
  for select using (investor_id = auth.uid() or public.is_admin());

create policy "submarkets_select_with_access" on submarkets
  for select using (public.has_market_access(market_id));

create policy "market_events_select_with_access" on market_events
  for select using (public.has_market_access(market_id));

create policy "market_metrics_select_with_access" on market_metrics
  for select using (public.has_market_access(market_id));

create policy "competitors_select_with_access" on competitors
  for select using (public.has_market_access(market_id));

create policy "leads_select_with_access" on leads
  for select using (public.has_market_access(market_id));

create policy "properties_select_own_or_admin" on properties
  for select using (investor_id = auth.uid() or public.is_admin());
create policy "properties_insert_own" on properties
  for insert with check (investor_id = auth.uid());
create policy "properties_update_own" on properties
  for update using (investor_id = auth.uid()) with check (investor_id = auth.uid());
create policy "properties_delete_own" on properties
  for delete using (investor_id = auth.uid());

-- Seed the first market. Coordinates are Davenport, IA's city center, used
-- only as the map's default view -- submarkets/events/metrics/competitors
-- are intentionally left empty for manual research to fill in.
insert into markets (slug, name, state, center_lat, center_lng, default_zoom)
values ('davenport-ia', 'Davenport', 'IA', 41.5236, -90.5776, 12);

-- To onboard an investor: create their auth user in Supabase Auth ->
-- Users (invite-only, no public sign-up), then grant their profile and
-- market access:
--
--   insert into investor_profiles (id, full_name, role)
--   values ('<their auth.users.id>', '<their name>', 'investor');
--
--   insert into investor_markets (investor_id, market_id)
--   select '<their auth.users.id>', id from markets where slug = 'davenport-ia';
--
-- To make someone an admin (can manage Development Intelligence signals
-- and sees every market), set role = 'admin' instead.

create index leads_market_idx on leads (market_id);
create index leads_market_absentee_idx on leads (market_id, is_absentee);
