-- Applied to project lzyppxkivzwdtsxdquso on 2026-09-29.
-- Adds TDOT's I-24 ramp centerlines and routes over them as one-way roads.
--
-- Source: TDOT Traffic Lines (FACILITY_TYPE = 4, COUNTY_NUMBER = 63)
-- https://services2.arcgis.com/nf3p7v7Zy4fTOh6M/arcgis/rest/services/Traffic_Lines/FeatureServer/0
-- On/off labels come from TDOT Travel Lanes Surface Area (i24_roads.geojson).
-- Every ramp is digitized in its direction of travel (off-ramps start at I-24,
-- on-ramps end there). TDOT has no line for exit 11 ramp A.
--
-- Roads.geojson has a single I-24 centerline, so short one-way connectors join
-- each ramp end to I-24 or to the crossroad it serves. The earlier rule that
-- joined I-24 to State Routes where they cross is no longer used.

create table public.ramps (
  id bigint generated always as identity primary key,
  route_id text not null unique,
  exit_number integer not null,
  ramp text not null,
  direction text not null,
  ramp_type text not null check (ramp_type in ('on', 'off')),
  aadt integer,
  geom extensions.geometry(LineString, 4326) not null
);

create index ramps_geom_idx on public.ramps using gist (geom);

alter table public.ramps enable row level security;
create policy "Public read access" on public.ramps for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.ramps from anon, authenticated;

insert into public.ramps (route_id, exit_number, ramp, direction, ramp_type, aadt, geom)
select route_id, exit_number, ramp, direction, ramp_type, aadt, extensions.st_setsrid(extensions.st_linefromencodedpolyline(e, 6), 4326)
from (values
  ('63I002401N0001C', 1, 'C', 'Westbound', 'off', 11439, 'yurzdAhoapeDcIzQmAvCkAvCmAxCmAvCmAvCmAtCoAvCoAtCoAtCoAtCqAtCoArCsArCuApCuAlC{AlC{AhC_BdCcBdCaB`CeB`CeB~BiBzBgBzBkBxBkBvBmBtBmBrBoBrBqBnBoBpBqBpBoBpBmBrBoBtBmBrBmBtBkBtBmBvBmBvBmBtBkBvBkBtBmBvBkBvBmBvBkBvBmBvBkBtBkBvBkBxBkBvBkBvBmBxBkBvBkBtBmBtBmBtBmBvBmBtBmBtBmBvBmBxBkBvBkBxBkBxBiBzBkB|BiBzBkBvBqBnByB~AsJjE'),
  ('63I002401N0001D', 1, 'D', 'Westbound', 'on', 3169, '}{zzdAzckpeD`HjFbBzBtAjC`AxCj@dDVlDNnDJpDJpDJpDHpDHnDFrDHpDHpDHpDHpDHrDHpDHrDHpDHpDHpDHrDHrDHpDHpDJrDHpDHrDHrDHpDFrDFrDFpDDrDDrDDpD@rDApDErDIpDOpDQpDSnD[nD]nDa@lDe@jDi@jDm@hDo@fDs@fDqRn{@'),
  ('63I002401N0004C', 4, 'C', 'Westbound', 'off', 8844, '_mrxdAbd`neDwUfO}BzA{BxA}BzA}BxA}BxA}BxA}BvA}BvA_CvA}BvA_CtA_CtA_CrAaCpAaCnAaCjAcChAeCbAeCbAgC|@gCz@iCx@iCx@iCv@iCt@iCt@iCr@kCr@iCr@kCr@kCp@iCp@kCr@kCp@kCp@iCr@kCp@iCr@kCr@iCr@kCp@kCr@kCr@iCr@kCr@kCr@iCr@kCr@iCr@kCr@kCp@iCr@kCr@kCp@iCr@kCp@kCn@iCn@mCl@kCl@mCj@kCj@mCh@kCh@mCh@mCh@mCl@kCl@mCp@iCp@kCr@kCr@kCt@kCr@kCt@kCt@kCr@kCn@mCb@oCLmCIuBc@oG}B'),
  ('63I002401N0004D', 4, 'D', 'Westbound', 'on', 9369, 'cv~xdA~sdneDjGt^RlDApDYnDi@fDy@~Cm@xBMb@_A~C{@~C}@bD{@`D}@`D}@`D{@bD}@`D{@bD{@bD{@bD{@bD{@`D}@bD{@`D}@`D}@bD}@~C}@bD}@`D}@`D}@bD{@`D}@`D_A`DaA~CaA~CcA|CeAzCiAzCiAvCmAvCoArCqArCsApCuApCwAjCyAlC}AfC}AdCaBdCaB`CeB~BeB|BgBzBiBxBgApA}`@pd@'),
  ('63I002401N0008C', 8, 'C', 'Westbound', 'off', 12744, 'y`}udAtt`leDeg@hLiCt@iCr@iCr@kCp@kCr@iCr@kCp@iCr@kCp@kCn@kCn@kCl@kCn@kCj@kCl@kCj@kCh@mCh@kCh@mCd@kCd@mCb@mCb@mCb@mCd@mC`@mCb@mCb@mCb@mC`@kCb@mC`@mC`@mC`@mC^mC`@mC^mC^mC^mC^oC^mC^oC^mC^mC^oC^oC`@mC^oCb@mC`@oC^mC`@oC`@mC^oC^oC^oC`@OB_CZoC`@mC`@mC^kCb@gCnAwBhBiBhB'),
  ('63I002401N0008D', 8, 'D', 'Westbound', 'on', 3299, 'migvdA~gcleDaDr@aATwA^cBd@uBpAkAr@mAt@sBjBqBhBsBhBsBhBsBhBqBfBsBhBsBjBqBjBqBhBsBjBsBjBsBhBsBjBqBhBsBjBuBhBsBhBuBhBsBhBsBhBsBjBsBhBuBhBsBjBsBjBuBhBsBjBsBhBuBhBsBjBsBhBuBhBsBhBwBhBuBfBuBfBuBfBwBfBuBdBwBdBwBbBwB`ByB~A{B~AyB|A{B|A{BzA{BzA{BxA}BvA_CvA_CrA_CrA_CrA_CrA_CnAaCpAy^jT'),
  ('63I002401N0011C', 11, 'C', 'Westbound', 'off', 6343, 'g{atdApuejeDeXb\iBxBkBxBiBxBiBxBkBzBkBvBkBxBkBtBkBtBoBrBmBpBqBnBsBlBqBjBuBhBsBhBuBfBwBfBwBdBwBdBwBdBwB`ByBbByB`ByB`ByBbByB`ByB~AyB`ByB`ByB~A{B`ByB`ByB~AyB`B{B~AyB`B{B~AyB~AyB`ByB~A{B`ByB~A{B`ByB~A{B~AyB`B{B~A{B~A{B~A{B|A}BxA_CtA_CrA_CrA_CvA_CxA}BzA}B|A}@n@_An@{B|A{B~A{BzAwB|AaA~@u@`A]l@'),
  ('63I002401N0011D', 11, 'D', 'Westbound', 'on', 11784, 'w}jtdArnljeDE`NYlDa@jDi@hDq@dDw@bD}@~C}@~CaA~C_A~C_A|C_@nA_@nAaA~C_A~C_A~C_A~C}@`D_A~C_A`D_A~C_A~C_A~C_A~C_A`D_A~C}@`D}@`D_A~C}@`DaA~C_A~C_A~CaA~C_A~CaA`DaA~C_A~C}@`D_A~C_A`D}@`D_A`D}@~C_A`D_A~C_A`DaA~CaA~CaA~CaA~CcA~CaA|CcA~CeAzCgAzCiAzCkAxCkAtCoAvCoAtCqArCqApCuArCuAnCwAlCyAjCyAlC{AjC{AhC_BhC}AfC_BfC}AfCeZ`i@'),
  ('63I002401P0001A', 1, 'A', 'Eastbound', 'off', 3304, 'onzzdAx}wpeDhTai@jAyChA{CjAyCjAyCjAyCjAyCjAyClAwCjAwCnAwClAwCnAwCpAsCpAuCpAsCtAqCtAoCxAmCxAkCzAiC~AgC~AeCbBaCbB_CfB}BfB}BhByBhB{BhByBhByBjBwBhByBjByBhBwBjByBhByBjByBhByBhByBhByBjByBhByBhByBjBwBhByBjByBjBwBhByBjBwBjByBhByBhByBjByBhByBjByBhBwBjBwBjByBjBwBjBwBjByBhByBjByBhByBjByBhByBjByBhByBjByBlByBjBwBlBwBlBwBnBuBnBuBrBmBxBaB`CkAlQsD'),
  ('63I002401P0001B', 1, 'B', 'Eastbound', 'on', 11461, '_}pzdApxlpeDwQ{GcCcAwB{AiBuBwAiCeAyCs@cDc@kDYmDUoDQqDOoDMsDOoDOqDOqDOqDOqDOqDOoDOsDOqDMoDOqDOsDMqDOsDOqDOqDOqDOsDMqDMqDMqDIsDIqDEqDCsD?qD@sDFqDHqDLqDNqDRqDVoDZmD^oD`@kDf@kDh@kDl@iDp@gDt@gDv@eDjWqiA'),
  ('63I002401P0004A', 4, 'A', 'Eastbound', 'off', 9573, 'wzcydA|fqneDdYsPzB{A|B}AzB{AzB{A|B{AzB{AzB{A|ByA|ByA|BwA~BwA|BwA~BuA~BsA`CoA`CmAdCiAbCgAbCgAfCaAdC}@hCy@hCy@hCu@hCu@hCs@jCq@jCq@jCo@jCo@hCo@lCq@jCo@jCo@jCo@jCo@jCq@jCq@jCq@jCq@jCq@jCo@lCq@jCo@jCo@lCm@jCo@jCo@lCo@hCo@lCo@jCq@jCo@jCq@jCq@jCo@jCo@jCm@jCo@lCo@jCq@jCo@hCq@jCq@hCs@jCo@jCq@hCq@jCq@jCq@jCs@hCq@jCq@XGnBi@jCo@lCe@jCUlCAlCXrUrG'),
  ('63I002401P0004B', 4, 'B', 'Eastbound', 'on', 7545, 'kxwxdA`rlneDuDaSSmDBmDVkDh@iDp@eDv@cDx@aDFSt@mCz@aDx@cDv@cDv@cDv@eDv@eDt@cDv@eDv@cDv@eDv@cDv@eDv@cDx@eDv@cDz@cDx@cDz@cDz@aD|@cD|@aD|@_D~@aD`A_DbA_DdA{ChA{CjAwCjAuCpAuCpAqCrAqCvAmCxAmCxAiC|AgC~AgC~AcC`BcCbBaCdB}BfB}BhByBhBwBlBsBlBuBnBqBnBoBpBmBpBmBrBkBrBkBrBkBpBmBrBkB`e@_g@'),
  ('63I002401P0008A', 8, 'A', 'Eastbound', 'off', 3659, '{ylvdAtfmleDzSkEjCs@hCs@jCq@jCs@jCq@hCq@jCq@jCq@jCo@lCm@jCk@jCi@lCg@lCc@nCc@lC_@nC_@lC]lCYnCYnCUpCUnCQnCQnCMnCOpCMnCMnCOpCOnCMnCMpCMpCMnCMpCKnCKpCKnCKpCKpCKnCKpCMpCMpCMpCKhHcAhHkB|LuE'),
  ('63I002401P0008B', 8, 'B', 'Eastbound', 'on', 13260, 'ovdvdA|mkleDpA]zDaA~FcCbCmAlDmCbB{@nBkBrBmBpBkBpBkBrBkBpBkBpBkBrBmBpBkBpBkBrBmBpBkBrBkBrBmBpBkBpBkBrBmBpBmBrBkBpBmBrBkBrBmBrBkBrBkBrBkBrBkBrBkBrBkBrBmBrBkBrBkBrBkBrBiBtBgBtBeBvBeBxBaBxB_BxB_BzB}AzB{AzB{A|BwA|BwA~BsA`CqA~BoA`CmAbCkAbCkArc@{V'),
  ('63I002401P0011B', 11, 'B', 'Eastbound', 'on', 6247, '_thtdAr_vjeDnAwIj@gDr@eDz@aD|@_D`A}C`A}C`A}C~@_D`A}C`A}C`A}C`A}C`A}CbA{C`A_D`A{CbA_DbA}C`A}CdA_DbA}CbA}C`A}C`A_D`A}CbA_D`A}CbA_D`A}CbA_D`A}CbA_D`A}CbA_D`A}CbA_DbA}CbA}CbA_D`A}CdA_DbA}CbA}CbA_DbA}CbA}C`A}CbA_DbA}CbA_DbA}CbA_D`A}CbA_D`A_D`A_D`A_DbA}CbA}CdA}CdA}CfAyCjAwClAwCnAsCpAsCtAqCtAmCvAmCxAkCxAkC|AiC|AgC|AgClVce@')
) v(route_id, exit_number, ramp, direction, ramp_type, aadt, e);

alter table public.road_edges add column one_way boolean not null default false;

-- Assumed speeds: Interstate 65 mph, State Route 45, Ramp 35, everything else 30.
create or replace function private.road_speed_mps(p_class text)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case p_class
    when 'Interstate' then 65
    when 'State Route' then 45
    when 'Ramp' then 35
    else 30
  end * 0.44704;
$$;

-- Rebuilds public.road_edges from public.roads and public.ramps.
create procedure private.build_network()
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  truncate public.road_edges restart identity;
  drop table if exists public.road_edges_vertices_pgr;

  -- 1. Lines. Interstates and ramps are grade separated: other roads only
  --    join them where a line ends on them, never where they cross.
  create temp table base (
    id bigint generated always as identity,
    route text,
    road_class text,
    one_way boolean,
    grade_separated boolean,
    geom geometry
  ) on commit drop;

  --    Unique Pavement centerlines (several Pavement rows can share one).
  insert into base (route, road_class, one_way, grade_separated, geom)
  select min(route), private.road_class(min(route)), false, min(route) like 'I%', g
  from (
    select route, (st_dump(st_snaptogrid(geom, 1e-7))).geom as g from public.roads
  ) d
  where st_length(g) > 0
  group by g;

  insert into base (route, road_class, one_way, grade_separated, geom)
  select route_id, 'Ramp', true, true, st_snaptogrid(geom, 1e-7) from public.ramps;

  create index on base using gist (geom);

  --    Connectors: the I-24 end of each ramp (start of an off-ramp, end of an
  --    on-ramp) joins the nearest point on I-24; the other end joins the
  --    nearest other road. Both follow the ramp's direction.
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
        and (b.route like 'I%') = ((r.ramp_type = 'off') = e.is_start)
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

  --    Endpoints. A grade-separated line is only split where one of its own
  --    kind ends or where another line dead-ends on it.
  insert into nodes
  select g, deg = 1 or on_grade_separated from ends;

  --    At-grade crossings between ordinary roads.
  insert into nodes
  select d.geom, false
  from base a
  join base b on a.id < b.id and st_intersects(a.geom, b.geom)
  cross join lateral st_dump(st_intersection(a.geom, b.geom)) d
  where not a.grade_separated and not b.grade_separated
    and st_geometrytype(d.geom) = 'ST_Point';

  --    Near misses: a dead end within ~2 m of another road joins it.
  insert into nodes
  select st_closestpoint(b.geom, e.g), true
  from ends e
  join base b on st_dwithin(b.geom, e.g, 2e-5) and not st_intersects(b.geom, e.g)
  where e.deg = 1;

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

-- Loading from private.staging (scripts/load_layers.py) now ends with build_network().
create or replace procedure private.build_layers()
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  truncate public.roads, public.marina_sites, public.school_properties,
           public.recreation_areas restart identity;

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

  call private.build_network();
end;
$$;

call private.build_network();

-- Ramps are drawn with the roads.
create or replace function public.get_roads()
returns json
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(json_agg(f), '[]'::json)
  )
  from (
    select json_build_object(
      'type', 'Feature',
      'id', r.id,
      'properties', json_build_object(
        'id', r.id, 'route', r.route, 'road_class', r.road_class,
        'width_ft', r.width_ft, 'begin_mile', r.begin_mile,
        'end_mile', r.end_mile, 'length_mi', r.length_mi),
      'geometry', st_asgeojson(st_simplify(r.geom, 1e-5), 5)::json
    ) as f
    from public.roads r
    union all
    select json_build_object(
      'type', 'Feature',
      'id', 1000000 + m.id,
      'properties', json_build_object(
        'id', 1000000 + m.id,
        'route', format('I-24 Exit %s %s %s-ramp', m.exit_number, lower(m.direction), m.ramp_type),
        'road_class', 'Ramp', 'width_ft', null, 'begin_mile', null, 'end_mile', null,
        'length_mi', round((st_length(m.geom::geography) / 1609.344)::numeric, 3)),
      'geometry', st_asgeojson(st_simplify(m.geom, 1e-5), 5)::json
    )
    from public.ramps m
  ) x;
$$;

-- Directed routing: ramps are one-way.
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
      format('select id, source, target, %1$I as cost,
                     case when one_way then -1 else %1$I end as reverse_cost
              from public.road_edges where connected', cost_col),
      format('select 1 as pid, %s::bigint as edge_id, %s::float8 as fraction
              union all select 2, %s::bigint, %s::float8', s.id, s.frac, e.id, e.frac),
      -1, -2, directed => true
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

grant select on public.ramps to anon, authenticated;
