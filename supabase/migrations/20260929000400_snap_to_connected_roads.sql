-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- A few short roads are cut off from the main network (gaps in the source data).
-- Mark edges in the main network and only snap route start/end points to those,
-- so a location next to a cut-off road still gets a route.

alter table public.road_edges add column connected boolean not null default true;

create or replace procedure private.mark_connected_edges()
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  create temp table comp on commit drop as
  select * from pgr_connectedComponents(
    'select id, source, target, length_m as cost, length_m as reverse_cost from public.road_edges');

  update public.road_edges e
  set connected = c.component = (select component from comp group by component order by count(*) desc limit 1)
  from comp c
  where c.node = e.source;
end;
$$;

call private.mark_connected_edges();

create or replace function public.get_route(
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
  -- Fractions stay just inside the edge: pgr_withPoints finds no path for a
  -- point exactly on an edge end.
  select re.id, least(greatest(st_linelocatepoint(re.geom, start_pt), 1e-6), 1 - 1e-6) as frac,
         st_distance(re.geom::geography, start_pt::geography) as snap_m
  into s
  from public.road_edges re
  where re.connected
  order by re.geom <-> start_pt
  limit 1;

  if not found then
    raise exception 'The road network is not loaded yet.';
  end if;

  select re.id, least(greatest(st_linelocatepoint(re.geom, end_pt), 1e-6), 1 - 1e-6) as frac,
         st_distance(re.geom::geography, end_pt::geography) as snap_m
  into e
  from public.road_edges re
  where re.connected
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
      format('select id, source, target, %1$I as cost, %1$I as reverse_cost from public.road_edges where connected', cost_col),
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
