-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- Map layers (roads, marina sites, school property, recreation areas), a routable
-- road network built with pgRouting, and read-only RPCs for the map.

-- ---------------------------------------------------------------------------
-- Layer tables
-- ---------------------------------------------------------------------------

-- Roads.geojson is TDOT roadway inventory: each segment is repeated once per
-- cross-section feature (Pavement, Drainage, Shoulder, ...) with the same
-- centerline. Only the Pavement rows are kept; they cover every route.
create table public.roads (
  id bigint generated always as identity primary key,
  objectid integer,
  route text not null,
  id_number text,
  road_class text not null,
  width_ft numeric,
  begin_mile numeric,
  end_mile numeric,
  length_mi numeric,
  geom extensions.geometry(MultiLineString, 4326) not null
);

create table public.marina_sites (
  id bigint generated always as identity primary key,
  name text,
  props jsonb not null,
  geom extensions.geometry(Point, 4326) not null
);

create table public.school_properties (
  id bigint generated always as identity primary key,
  name text,
  district text,
  props jsonb not null,
  geom extensions.geometry(MultiPolygon, 4326) not null
);

create table public.recreation_areas (
  id bigint generated always as identity primary key,
  name text,
  props jsonb not null,
  geom extensions.geometry(MultiPolygon, 4326) not null
);

-- Routable network: Pavement centerlines split at intersections.
create table public.road_edges (
  id bigint generated always as identity primary key,
  route text not null,
  road_class text not null,
  source bigint,
  target bigint,
  length_m double precision not null,
  travel_s double precision not null,
  geom extensions.geometry(LineString, 4326) not null
);

create index roads_geom_idx on public.roads using gist (geom);
create index marina_sites_geom_idx on public.marina_sites using gist (geom);
create index school_properties_geom_idx on public.school_properties using gist (geom);
create index recreation_areas_geom_idx on public.recreation_areas using gist (geom);
create index road_edges_geom_idx on public.road_edges using gist (geom);
create index road_edges_source_idx on public.road_edges (source);
create index road_edges_target_idx on public.road_edges (target);

-- Read-only for the public map: RLS on, SELECT only, no write policies.
do $$
declare t text;
begin
  foreach t in array array['roads', 'marina_sites', 'school_properties', 'recreation_areas', 'road_edges'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "Public read access" on public.%I for select to anon, authenticated using (true)', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Build the layers and the routing network from private.staging
-- ---------------------------------------------------------------------------

-- Assumed speeds (no speed data in the source): Interstate 65 mph,
-- State Route 45 mph, everything else 30 mph.
create function private.road_class(p_route text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_route like 'I%' then 'Interstate'
    when p_route like 'SR%' then 'State Route'
    else 'Local'
  end;
$$;

create function private.road_speed_mps(p_class text)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case p_class
    when 'Interstate' then 65
    when 'State Route' then 45
    else 30
  end * 0.44704;
$$;

create procedure private.build_layers()
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  truncate public.roads, public.marina_sites, public.school_properties,
           public.recreation_areas, public.road_edges restart identity;
  drop table if exists public.road_edges_vertices_pgr;

  insert into public.roads (objectid, route, id_number, road_class, width_ft,
                            begin_mile, end_mile, length_mi, geom)
  select (props->>'OBJECTID')::integer, props->>'NBR_RTE', props->>'ID_NUMBER',
         private.road_class(props->>'NBR_RTE'), (props->>'FEAT_WIDTH')::numeric,
         (props->>'RD_BEG_LOG_MLE')::numeric, (props->>'RD_END_LOG_MLE')::numeric,
         (props->>'LOG_MLE_LENGTH')::numeric, st_multi(geom)
  from private.staging
  where layer = 'roads' and props->>'TYP_FEAT' = 'Pavement';

  insert into public.marina_sites (name, props, geom)
  select props->>'Name', props, geom
  from private.staging where layer = 'marina_sites';

  insert into public.school_properties (name, district, props, geom)
  select props->>'School', props->>'District', props,
         st_multi(st_collectionextract(st_makevalid(geom), 3))
  from private.staging where layer = 'school_properties';

  insert into public.recreation_areas (name, props, geom)
  select props->>'Name', props, st_multi(st_collectionextract(st_makevalid(geom), 3))
  from private.staging where layer = 'recreation_areas';

  -- 1. Unique centerlines (several Pavement rows can share one centerline).
  create temp table base on commit drop as
  select row_number() over () as id, min(route) as route, g as geom
  from (
    select route, (st_dump(st_snaptogrid(geom, 1e-7))).geom as g from public.roads
  ) d
  where st_length(g) > 0
  group by g;
  create index on base using gist (geom);

  -- 2. Split points.
  --    Endpoints: every line end. Interstates are only split where one of their
  --    own segments ends or where another line dead-ends on them (a ramp), so a
  --    road that passes over or under them does not become a junction.
  create temp table ends on commit drop as
  select g, count(*) as deg, bool_or(route like 'I%') as on_interstate
  from (
    select route, st_startpoint(geom) as g from base
    union all
    select route, st_endpoint(geom) from base
  ) e
  group by g;

  create temp table nodes (g geometry, interstate_ok boolean) on commit drop;

  insert into nodes
  select g, deg = 1 or on_interstate from ends;

  --    Crossings between non-interstate roads (at-grade intersections that were
  --    digitized without a shared vertex).
  insert into nodes
  select d.geom, false
  from base a
  join base b on a.id < b.id and st_intersects(a.geom, b.geom)
  cross join lateral st_dump(st_intersection(a.geom, b.geom)) d
  where a.route not like 'I%' and b.route not like 'I%'
    and st_geometrytype(d.geom) = 'ST_Point';

  --    Near misses: a dead end within ~2 m of another road joins it.
  insert into nodes
  select st_closestpoint(b.geom, e.g), true
  from ends e
  join base b on st_dwithin(b.geom, e.g, 2e-5) and not st_intersects(b.geom, e.g)
  where e.deg = 1;

  create index on nodes using gist (g);

  -- 3. Split each line at the points that apply to it.
  insert into public.road_edges (route, road_class, length_m, travel_s, geom)
  select s.route, private.road_class(s.route),
         st_length(s.geom::geography),
         st_length(s.geom::geography) / private.road_speed_mps(private.road_class(s.route)),
         s.geom
  from (
    select b.route, (st_dump(
             case when p.mp is null then b.geom
                  else st_split(st_snap(b.geom, p.mp, 1e-6), p.mp) end
           )).geom as geom
    from base b
    left join lateral (
      select st_collect(n.g) as mp
      from nodes n
      where st_dwithin(n.g, b.geom, 1e-6)
        and (n.interstate_ok or b.route not like 'I%')
        and not st_dwithin(n.g, st_startpoint(b.geom), 1e-7)
        and not st_dwithin(n.g, st_endpoint(b.geom), 1e-7)
    ) p on true
  ) s
  where st_geometrytype(s.geom) = 'ST_LineString' and st_length(s.geom) > 0;

  -- 4. Topology: endpoints within ~2 m share a vertex.
  perform pgr_createTopology('public.road_edges', 2e-5, 'geom', 'id', 'source', 'target');

  alter table public.road_edges_vertices_pgr enable row level security;
  revoke all on public.road_edges_vertices_pgr from anon, authenticated;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read-only RPCs for the map (GeoJSON FeatureCollections)
-- ---------------------------------------------------------------------------

create function public.get_roads()
returns json
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(json_build_object(
      'type', 'Feature',
      'id', r.id,
      'properties', json_build_object(
        'id', r.id, 'route', r.route, 'road_class', r.road_class,
        'width_ft', r.width_ft, 'begin_mile', r.begin_mile,
        'end_mile', r.end_mile, 'length_mi', r.length_mi),
      'geometry', st_asgeojson(st_simplify(r.geom, 1e-5), 5)::json
    )), '[]'::json)
  )
  from public.roads r;
$$;

create function public.get_marina_sites()
returns json
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(json_build_object(
      'type', 'Feature',
      'id', m.id,
      'properties', m.props || jsonb_build_object('id', m.id),
      'geometry', st_asgeojson(m.geom, 6)::json
    )), '[]'::json)
  )
  from public.marina_sites m;
$$;

-- The source file is statewide; the map only needs the schools around the roads.
create function public.get_school_properties()
returns json
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(json_build_object(
      'type', 'Feature',
      'id', s.id,
      'properties', s.props || jsonb_build_object('id', s.id),
      'geometry', st_asgeojson(s.geom, 6)::json
    )), '[]'::json)
  )
  from public.school_properties s
  where s.geom && (select st_setsrid(st_extent(geom)::geometry, 4326) from public.roads);
$$;

create function public.get_recreation_areas()
returns json
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(json_build_object(
      'type', 'Feature',
      'id', a.id,
      'properties', a.props || jsonb_build_object('id', a.id),
      'geometry', st_asgeojson(a.geom, 6)::json
    )), '[]'::json)
  )
  from public.recreation_areas a;
$$;

-- ---------------------------------------------------------------------------
-- Routing
-- ---------------------------------------------------------------------------

-- Route between two lon/lat points over public.road_edges.
-- p_mode: 'distance' (shortest) or 'time' (fastest, using the assumed speeds).
-- All roads are treated as two-way; the source data has no one-way flags.
create function public.get_route(
  start_lon double precision, start_lat double precision,
  end_lon double precision, end_lat double precision,
  p_mode text default 'distance'
)
returns json
language plpgsql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
declare
  max_snap_m constant double precision := 3000;
  start_pt geometry := st_setsrid(st_makepoint(start_lon, start_lat), 4326);
  end_pt geometry := st_setsrid(st_makepoint(end_lon, end_lat), 4326);
  s record;
  e record;
  cost_col text := case when p_mode = 'time' then 'travel_s' else 'length_m' end;
  route_geom geometry;
  dist_m double precision;
  time_s double precision;
begin
  select re.id, st_linelocatepoint(re.geom, start_pt) as frac,
         st_distance(re.geom::geography, start_pt::geography) as snap_m
  into s
  from public.road_edges re
  order by re.geom <-> start_pt
  limit 1;

  if not found then
    raise exception 'The road network is not loaded yet.';
  end if;

  select re.id, st_linelocatepoint(re.geom, end_pt) as frac,
         st_distance(re.geom::geography, end_pt::geography) as snap_m
  into e
  from public.road_edges re
  order by re.geom <-> end_pt
  limit 1;

  if s.snap_m > max_snap_m then
    raise exception 'The starting point is more than 3 km from a Montgomery County road.';
  end if;
  if e.snap_m > max_snap_m then
    raise exception 'The destination is more than 3 km from a Montgomery County road.';
  end if;

  -- Points are -1 (start) and -2 (destination); each step runs from one node
  -- to the next, so trim the first and last edges at the snapped fractions.
  with path as (
    select p.path_seq, p.node, p.edge,
           lead(p.node) over (order by p.path_seq) as next_node
    from pgr_withPoints(
      format('select id, source, target, %1$I as cost, %1$I as reverse_cost from public.road_edges', cost_col),
      format('select 1 as pid, %s::bigint as edge_id, %s::float8 as fraction
              union all select 2, %s::bigint, %s::float8', s.id, s.frac, e.id, e.frac),
      -1, -2, directed => false
    ) p
  ),
  steps as (
    select p.path_seq, re.geom, re.travel_s / nullif(re.length_m, 0) as s_per_m,
           case p.node when -1 then s.frac when -2 then e.frac
                       when re.source then 0 else 1 end as a,
           case p.next_node when -1 then s.frac when -2 then e.frac
                            when re.source then 0 else 1 end as b
    from path p
    join public.road_edges re on re.id = p.edge
    where p.edge <> -1
  ),
  segs as (
    select path_seq, s_per_m,
           case when a <= b then st_linesubstring(geom, a, b)
                else st_reverse(st_linesubstring(geom, b, a)) end as g
    from steps
    where a <> b
  )
  select st_linemerge(st_collect(g order by path_seq)),
         sum(st_length(g::geography)),
         sum(st_length(g::geography) * coalesce(s_per_m, 0))
  into route_geom, dist_m, time_s
  from segs;

  if route_geom is null then
    raise exception 'No route was found between those points.';
  end if;

  return json_build_object(
    'type', 'FeatureCollection',
    'features', json_build_array(json_build_object(
      'type', 'Feature',
      'properties', json_build_object(
        'mode', case when p_mode = 'time' then 'time' else 'distance' end,
        'distance_m', round(dist_m::numeric, 1),
        'duration_s', round(time_s::numeric),
        'start_snap_m', round(s.snap_m::numeric, 1),
        'end_snap_m', round(e.snap_m::numeric, 1)),
      'geometry', st_asgeojson(route_geom, 6)::json
    ))
  );
end;
$$;

grant execute on function public.get_roads() to anon, authenticated;
grant execute on function public.get_marina_sites() to anon, authenticated;
grant execute on function public.get_school_properties() to anon, authenticated;
grant execute on function public.get_recreation_areas() to anon, authenticated;
grant execute on function public.get_route(double precision, double precision, double precision, double precision, text) to anon, authenticated;
