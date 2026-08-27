-- Opportunities and Catalysts intelligence layers (app.roqhome.com
-- /dashboard/development-map). Sibling layers to Pipeline (projects table,
-- 20260810000000_development_intelligence_schema.sql), same source
-- discipline: every row cites a `sources` row, carries confidence +
-- last_verified_at, admin-only writes gated by is_admin(), read access
-- gated by has_market_access(market_id) -- both functions already exist
-- from 20260809010000_dashboard_schema.sql.
--
-- Opportunities is a new table rather than an extension of the existing
-- `leads` table: `leads` is bulk-imported, uncurated county-record data
-- with no individual source citation and no lat/lng (list-view only).
-- Opportunities is individually curated and source-cited, the same bar as
-- Pipeline's `projects` -- so it gets its own table, with an optional
-- nullable `lead_id` back to `leads` for traceability when an opportunity
-- originated from surfacing a specific bulk lead, without blurring the two
-- tables' very different curation guarantees.
--
-- Buildability (the fourth layer) is intentionally not represented here --
-- it's parcel-level zoning/regulatory attribute data, not a signal feed,
-- and needs a different schema shape. Separate future migration.

create table opportunities (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  lead_id uuid references leads (id) on delete set null,

  address text not null,
  latitude double precision not null,
  longitude double precision not null,

  opportunity_type text not null check (
    opportunity_type in ('pre_foreclosure', 'tax_lien', 'tax_delinquent', 'listing', 'off_market', 'distressed', 'land_opportunity')
  ),
  listing_status text, -- free text, e.g. "Active", "Under Contract", "Not Listed"

  owner_name text,
  is_absentee boolean,
  years_owned int,
  estimated_equity numeric,
  assessed_value numeric,
  distress_indicators text[], -- e.g. {tax_delinquent, code_violation, vacant}

  opportunity_score int check (opportunity_score between 0 and 100),
  why_flagged text not null, -- required: no opportunity ships without a stated rationale

  date_identified date,
  source_id uuid not null references sources (id) on delete restrict,
  confidence text not null default 'reported' check (
    confidence in ('verified', 'reported', 'unconfirmed')
  ),
  last_verified_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

create table catalysts (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,

  title text not null,
  catalyst_type text not null check (
    catalyst_type in ('major_employer', 'infrastructure_project', 'institutional', 'public_facility', 'mixed_use_anchor', 'other')
  ),
  description text,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  influence_radius_meters numeric not null default 800, -- ~0.5 mile default influence zone

  status text not null default 'planned' check (
    status in ('planned', 'under_construction', 'operating', 'completed')
  ),
  estimated_value numeric,

  date_announced date,
  source_id uuid not null references sources (id) on delete restrict,
  confidence text not null default 'reported' check (
    confidence in ('verified', 'reported', 'unconfirmed')
  ),
  last_verified_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

alter table opportunities enable row level security;
alter table catalysts enable row level security;

create policy "opportunities_select_with_access" on opportunities
  for select using (public.has_market_access(market_id));
create policy "opportunities_write_admin" on opportunities
  for all using (public.is_admin()) with check (public.is_admin());

create policy "catalysts_select_with_access" on catalysts
  for select using (public.has_market_access(market_id));
create policy "catalysts_write_admin" on catalysts
  for all using (public.is_admin()) with check (public.is_admin());

create index opportunities_market_idx on opportunities (market_id);
create index opportunities_market_type_idx on opportunities (market_id, opportunity_type);
create index catalysts_market_idx on catalysts (market_id);
