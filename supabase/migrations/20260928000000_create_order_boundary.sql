-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-28.
-- Data was loaded separately from ~/Downloads/base-postgresql-en/order_boundary.txt
-- (md5 0ec3e013f999001eba600e238001728e) via st_geomfromgeojson.

create extension if not exists postgis with schema extensions;

create table public.order_boundary (
  id bigint generated always as identity primary key,
  name text not null default 'Order boundary',
  geom extensions.geometry(MultiPolygon, 4326) not null,
  created_at timestamptz not null default now()
);

create index order_boundary_geom_idx on public.order_boundary using gist (geom);

-- Read-only for the public map: RLS on, SELECT only, no write policies.
alter table public.order_boundary enable row level security;

create policy "Public read access"
  on public.order_boundary for select
  to anon, authenticated
  using (true);

revoke insert, update, delete, truncate on public.order_boundary from anon, authenticated;

-- Returns all boundaries as a GeoJSON FeatureCollection for the map.
create or replace function public.get_order_boundary()
returns json
language sql
stable
security invoker
set search_path = ''
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(json_build_object(
      'type', 'Feature',
      'id', b.id,
      'properties', json_build_object('id', b.id, 'name', b.name),
      'geometry', extensions.st_asgeojson(b.geom)::json
    )), '[]'::json)
  )
  from public.order_boundary b;
$$;

grant execute on function public.get_order_boundary() to anon, authenticated;
