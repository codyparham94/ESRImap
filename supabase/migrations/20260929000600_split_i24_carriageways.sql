-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- Roads.geojson has one I-24 centerline for both directions, so routes could
-- take an eastbound ramp and then drive west. Model I-24 as two one-way
-- carriageways: TDOT's line is the eastbound (P) one (eastbound ramps touch it),
-- and a copy ~20 m to its left, reversed, is westbound (N). Ramps only join the
-- carriageway for their direction. Only ramps join the interstate.

create or replace procedure private.build_network()
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  truncate public.road_edges restart identity;
  drop table if exists public.road_edges_vertices_pgr;

  -- 1. Lines. Interstates and ramps are grade separated: other roads never
  --    join them; ramps join them through the connectors below.
  create temp table base (
    id bigint generated always as identity,
    route text,
    road_class text,
    one_way boolean,
    grade_separated boolean,
    carriageway text,
    geom geometry
  ) on commit drop;

  --    Unique Pavement centerlines (several Pavement rows can share one).
  insert into base (route, road_class, one_way, grade_separated, geom)
  select min(route), private.road_class(min(route)), false, false, g
  from (
    select route, (st_dump(st_snaptogrid(geom, 1e-7))).geom as g
    from public.roads
    where route not like 'I%'
  ) d
  where st_length(g) > 0
  group by g;

  --    I-24 carriageways. Eastbound runs northwest to southeast through the
  --    county (exit 1 to exit 11), which orients each merged line.
  insert into base (route, road_class, one_way, grade_separated, carriageway, geom)
  select 'I0024', 'Interstate', true, true, c.carriageway, d.geom
  from (
    select case when (st_x(st_endpoint(l)) - st_x(st_startpoint(l))) * 0.095
                   - (st_y(st_endpoint(l)) - st_y(st_startpoint(l))) * 0.105 < 0
                then st_reverse(l) else l end as eastbound
    from (
      select (st_dump(st_linemerge(st_union(st_snaptogrid(geom, 1e-7))))).geom as l
      from public.roads
      where route like 'I%'
    ) m
  ) o
  cross join lateral (values
    ('P', o.eastbound),
    ('N', st_reverse(st_offsetcurve(o.eastbound, 0.0002)))
  ) c(carriageway, g)
  cross join lateral st_dump(c.g) d
  where st_length(d.geom) > 0;

  insert into base (route, road_class, one_way, grade_separated, carriageway, geom)
  select route_id, 'Ramp', true, true, substr(route_id, 10, 1), st_snaptogrid(geom, 1e-7)
  from public.ramps;

  create index on base using gist (geom);

  --    Connectors: the I-24 end of each ramp (start of an off-ramp, end of an
  --    on-ramp) joins the nearest point on its own carriageway; the other end
  --    joins the nearest ordinary road. Both follow the ramp's direction.
  insert into base (route, road_class, one_way, grade_separated, geom)
  select l.route_id, 'Ramp', true, true,
         case when l.is_start then st_makeline(l.pt_on_road, l.pt) else st_makeline(l.pt, l.pt_on_road) end
  from (
    select r.route_id, e.is_start, e.pt, t.pt_on_road
    from public.ramps r
    cross join lateral (values (true, st_startpoint(r.geom)), (false, st_endpoint(r.geom))) e(is_start, pt)
    cross join lateral (
      select st_snaptogrid(st_closestpoint(b.geom, e.pt), 1e-7) as pt_on_road
      from base b
      where b.road_class <> 'Ramp'
        and case when (r.ramp_type = 'off') = e.is_start
                 then b.carriageway = substr(r.route_id, 10, 1)
                 else not b.grade_separated end
        and st_dwithin(b.geom, e.pt, 0.004)
      order by b.geom <-> e.pt
      limit 1
    ) t
  ) l
  where not st_equals(l.pt, l.pt_on_road);

  -- 2. Split points.
  create temp table ends on commit drop as
  select g, count(*) as deg, bool_or(grade_separated) as on_grade_separated
  from (
    select grade_separated, st_startpoint(geom) as g from base
    union all
    select grade_separated, st_endpoint(geom) from base
  ) e
  group by g;

  create temp table nodes (g geometry, grade_separated_ok boolean) on commit drop;

  --    Endpoints. A grade-separated line is only split where a ramp,
  --    connector or interstate line ends on it.
  insert into nodes
  select g, on_grade_separated from ends;

  --    At-grade crossings between ordinary roads.
  insert into nodes
  select d.geom, false
  from base a
  join base b on a.id < b.id and st_intersects(a.geom, b.geom)
  cross join lateral st_dump(st_intersection(a.geom, b.geom)) d
  where not a.grade_separated and not b.grade_separated
    and st_geometrytype(d.geom) = 'ST_Point';

  --    Near misses: a dead end within ~2 m of an ordinary road joins it.
  insert into nodes
  select st_closestpoint(b.geom, e.g), false
  from ends e
  join base b on st_dwithin(b.geom, e.g, 2e-5) and not st_intersects(b.geom, e.g)
  where e.deg = 1 and not b.grade_separated;

  create index on nodes using gist (g);

  -- 3. Split each line at the points that apply to it.
  insert into public.road_edges (route, road_class, one_way, length_m, travel_s, geom)
  select s.route, s.road_class, s.one_way,
         st_length(s.geom::geography),
         st_length(s.geom::geography) / private.road_speed_mps(s.road_class),
         s.geom
  from (
    select b.route, b.road_class, b.one_way, (st_dump(
             case when p.mp is null then b.geom
                  else st_split(st_snap(b.geom, p.mp, 1e-6), p.mp) end
           )).geom as geom
    from base b
    left join lateral (
      select st_collect(n.g) as mp
      from nodes n
      where st_dwithin(n.g, b.geom, 1e-6)
        and (n.grade_separated_ok or not b.grade_separated)
        and not st_dwithin(n.g, st_startpoint(b.geom), 1e-7)
        and not st_dwithin(n.g, st_endpoint(b.geom), 1e-7)
    ) p on true
  ) s
  where st_geometrytype(s.geom) = 'ST_LineString' and st_length(s.geom) > 0;

  -- 4. Topology: endpoints within ~2 m share a vertex.
  perform pgr_createTopology('public.road_edges', 2e-5, 'geom', 'id', 'source', 'target');

  alter table public.road_edges_vertices_pgr enable row level security;
  revoke all on public.road_edges_vertices_pgr from anon, authenticated;

  call private.mark_connected_edges();
end;
$$;

call private.build_network();
