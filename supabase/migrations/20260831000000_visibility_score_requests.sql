-- Free Visibility Score intake (roqbusiness.com home page CTA).
--
-- Public lead capture, so the trust model is inverted from the rest of the
-- schema: rows arrive from anonymous visitors rather than authenticated
-- investors. Nothing here grants the anon role any access -- the edge
-- function visibility-score-request writes with the service role key, which
-- bypasses RLS, and the only policy below is an admin read. That way the
-- publishable key shipped in the page can reach the function but can never
-- read the queue back out.
--
-- contact holds either an email address or a phone number depending on
-- contact_method, because the form asks the visitor which they prefer and
-- collects exactly one. Keeping them in a single column (rather than
-- nullable email + nullable phone) means "how to reach them" is always one
-- unambiguous value.

create table visibility_score_requests (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  city text not null, -- free text as typed, e.g. "Topeka, KS"
  website text, -- optional; stored as entered, may lack a scheme
  contact_method text not null check (contact_method in ('email', 'text')),
  contact text not null, -- email address or phone, per contact_method
  status text not null default 'new' check (
    status in ('new', 'in_progress', 'sent', 'archived')
  ),
  source text not null default 'roqbusiness.com', -- which surface sent it
  user_agent text, -- coarse spam/debugging signal only
  created_at timestamptz not null default now()
);

alter table visibility_score_requests enable row level security;

-- No anon or authenticated policy on purpose: inserts come from the edge
-- function's service-role client, which is not subject to RLS. Admins read
-- the queue and move rows through status; one `for all` policy covers both.
create policy "visibility_score_requests_admin" on visibility_score_requests
  for all using (public.is_admin()) with check (public.is_admin());

-- Working the queue means "oldest unhandled first", so status leads.
create index visibility_score_requests_status_idx
  on visibility_score_requests (status, created_at desc);
create index visibility_score_requests_created_idx
  on visibility_score_requests (created_at desc);
