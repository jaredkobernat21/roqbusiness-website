-- Narrows Opportunities to the "Properties" taxonomy the product settled
-- on (tax lien, pre-foreclosure, absentee owner, high-equity owner,
-- listing) and adds fields to support three things a Property's detail
-- panel now shows on click: distance from the nearest Activity signal
-- (computed client-side, no schema needed), investment potential (asking
-- price vs. estimated resale value), and buildability enrichment (zoning,
-- permitted uses, rezoning potential, fire-code/other notes). Buildability
-- stays enrichment data on a Property, not a separate parcel-attribute
-- table -- that remains a distinct future effort requiring real municipal
-- zoning-ordinance research.
--
-- is_absentee and years_owned already exist and directly serve the new
-- absentee_owner / high_equity_owner types.

alter table opportunities drop constraint if exists opportunities_opportunity_type_check;
alter table opportunities add constraint opportunities_opportunity_type_check
  check (opportunity_type in ('tax_lien', 'pre_foreclosure', 'absentee_owner', 'high_equity_owner', 'listing'));

alter table opportunities
  add column asking_price numeric,
  add column estimated_resale_value numeric,
  add column zoning_district text,
  add column permitted_uses text,
  add column rezoning_potential text,
  add column buildability_notes text;
