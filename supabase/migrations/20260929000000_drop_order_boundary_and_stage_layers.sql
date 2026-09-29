-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- Removes the old order boundary and sets up a temporary, token-protected loader
-- that scripts/load_layers.py uses to upload the GeoJSON files.

drop function if exists public.get_order_boundary();
drop table if exists public.order_boundary;

create extension if not exists pgrouting with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.staging (
  id bigint generated always as identity primary key,
  layer text not null,
  props jsonb not null,
  geom extensions.geometry(Geometry, 4326) not null
);

create table private.load_token (token text primary key);
insert into private.load_token values (encode(extensions.gen_random_bytes(24), 'hex'));

-- Temporary loader, dropped once the data is in place.
create function public.stage_features(p_token text, p_layer text, p_features jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  if not exists (select 1 from private.load_token where token = p_token) then
    raise exception 'invalid token';
  end if;
  insert into private.staging (layer, props, geom)
  select p_layer, f->'properties',
         extensions.st_setsrid(extensions.st_force2d(extensions.st_geomfromgeojson(f->'geometry')), 4326)
  from jsonb_array_elements(p_features) f
  where f->'geometry' is not null and f->'geometry' <> 'null'::jsonb;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.stage_features(text, text, jsonb) from public, authenticated;
grant execute on function public.stage_features(text, text, jsonb) to anon;
