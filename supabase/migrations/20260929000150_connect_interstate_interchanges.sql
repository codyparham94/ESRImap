-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- Roads.geojson has no ramps, so I-24 was cut off from the rest of the network.
-- In Montgomery County every State Route that crosses I-24 is an interchange
-- (exits 1, 4, 8 and 11: SR 48, SR 13, SR 237, SR 76), so join the interstate
-- to State Routes where they cross. Local roads that cross it stay bridges.

create or replace procedure private.build_layers()
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
  --    own segments ends or where another line dead-ends on them, so a road that
  --    passes over or under them does not become a junction.
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

  --    Crossings: at-grade intersections between non-interstate roads, plus
  --    interchanges where an interstate crosses a State Route.
  insert into nodes
  select d.geom, a.route like 'I%' or b.route like 'I%'
  from base a
  join base b on a.id < b.id and st_intersects(a.geom, b.geom)
  cross join lateral st_dump(st_intersection(a.geom, b.geom)) d
  where st_geometrytype(d.geom) = 'ST_Point'
    and (
      (a.route not like 'I%' and b.route not like 'I%')
      or (a.route like 'I%' and b.route like 'SR%')
      or (a.route like 'SR%' and b.route like 'I%')
    );

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
