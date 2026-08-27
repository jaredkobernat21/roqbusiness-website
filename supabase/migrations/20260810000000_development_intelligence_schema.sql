-- Development Intelligence schema (app.roqhome.com /dashboard/development-map).
--
-- Reusable across markets: every signal belongs to a market via market_id
-- and carries lat/lng so it renders on the map without per-city code
-- changes. Sits alongside the existing market_events table (kept for the
-- simple dashboard feed) rather than replacing it -- projects is the
-- richer model going forward.
--
-- Source discipline: every project traces to a row in `sources` (agency +
-- URL) and carries confidence + last_verified_at, so nothing on the map
-- claims more certainty than the underlying document supports. Status
-- changes are appended to project_updates, never overwritten in place, so
-- a project's progression (proposed -> ... -> completed) stays auditable.

create table sources (
  id uuid primary key default gen_random_uuid(),
  agency text not null, -- publisher of record, e.g. "City of Topeka Planning Department"
  title text, -- document/article title, e.g. "Planning Commission Agenda — June 2026"
  source_type text not null check (
    source_type in ('agency_document', 'agency_gis', 'press_release', 'news', 'public_record', 'other')
  ),
  url text not null,
  published_date date,
  created_at timestamptz not null default now()
);

create table parcels (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  parcel_number text, -- county assessor/APN identifier, when known
  address text,
  acreage numeric,
  boundary jsonb, -- geojson polygon/multipolygon in WGS84; null until traced
  source_id uuid references sources (id) on delete set null,
  created_at timestamptz not null default now()
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references markets (id) on delete cascade,
  parcel_id uuid references parcels (id) on delete set null,

  title text not null,
  category text not null check (
    category in ('active_development', 'planning_entitlement', 'zoning', 'infrastructure', 'land_transaction', 'business_announcement')
  ),
  subcategory text, -- free-form detail, e.g. "multifamily", "rezoning: R-1 to C-2", "road expansion"
  status text not null check (
    status in ('proposed', 'planning_review', 'filed', 'under_review', 'approved', 'permitted', 'under_construction', 'completed', 'on_hold', 'cancelled')
  ),

  description text,
  address text,
  latitude double precision not null,
  longitude double precision not null,

  project_value numeric, -- USD, when stated by the source
  units int, -- residential/commercial unit count, when applicable
  acreage numeric,
  developer text,

  date_announced date,
  date_updated date not null default current_date, -- bumped by trigger whenever the row changes

  source_id uuid not null references sources (id) on delete restrict,
  confidence text not null default 'reported' check (
    confidence in ('verified', 'reported', 'unconfirmed')
  ),
  last_verified_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

-- Append-only progression log. projects.status/date_updated always reflect
-- the latest row here, but nothing is ever overwritten -- this is what
-- lets us show "Proposed -> Planning Review -> Approved -> ..." over time.
create table project_updates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects (id) on delete cascade,
  status text not null check (
    status in ('proposed', 'planning_review', 'filed', 'under_review', 'approved', 'permitted', 'under_construction', 'completed', 'on_hold', 'cancelled')
  ),
  note text,
  source_id uuid references sources (id) on delete set null,
  occurred_on date not null default current_date,
  created_by uuid references investor_profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create function public.touch_project_date_updated()
returns trigger
language plpgsql
as $$
begin
  new.date_updated = current_date;
  return new;
end;
$$;

create trigger projects_touch_date_updated
  before update on projects
  for each row execute procedure public.touch_project_date_updated();

alter table sources enable row level security;
alter table parcels enable row level security;
alter table projects enable row level security;
alter table project_updates enable row level security;

-- Sources aren't market-scoped (an agency can be cited across markets) and
-- carry nothing sensitive -- readable by any signed-in user, same as the
-- projects that cite them.
create policy "sources_select_authenticated" on sources
  for select using (auth.role() = 'authenticated');
create policy "sources_write_admin" on sources
  for all using (public.is_admin()) with check (public.is_admin());

create policy "parcels_select_with_access" on parcels
  for select using (public.has_market_access(market_id));
create policy "parcels_write_admin" on parcels
  for all using (public.is_admin()) with check (public.is_admin());

create policy "projects_select_with_access" on projects
  for select using (public.has_market_access(market_id));
create policy "projects_write_admin" on projects
  for all using (public.is_admin()) with check (public.is_admin());

create policy "project_updates_select_with_access" on project_updates
  for select using (
    exists (
      select 1 from projects p
      where p.id = project_updates.project_id and public.has_market_access(p.market_id)
    )
  );
create policy "project_updates_write_admin" on project_updates
  for all using (public.is_admin()) with check (public.is_admin());

create index parcels_market_idx on parcels (market_id);
create index projects_market_idx on projects (market_id);
create index projects_market_category_idx on projects (market_id, category);
create index projects_market_status_idx on projects (market_id, status);
create index project_updates_project_idx on project_updates (project_id);

-- Seed Topeka as a market (real city-center coordinates, used only as the
-- map's default view -- intentionally zero projects/sources/parcels until
-- verified signals are researched and confirmed).
insert into markets (slug, name, state, center_lat, center_lng, default_zoom)
values ('topeka-ks', 'Topeka', 'KS', 39.0473, -95.6752, 12);

-- Grant an investor access the same way as Davenport:
--
--   insert into investor_markets (investor_id, market_id)
--   select '<their auth.users.id>', id from markets where slug = 'topeka-ks';
