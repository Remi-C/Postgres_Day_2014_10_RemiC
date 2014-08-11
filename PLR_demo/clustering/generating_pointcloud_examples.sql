
	CREATE TABLE temp_toto_demo AS 
	WITH patch AS (	
		SELECT *, PC_NUmPoints(patch)
		FROM acquisition_tmob_012013.riegl_pcpatch_space  
		WHERE
		-- PC_NumPoints(patch) BETWEEN 200 AND 1000 AND
		gid = 100029
		LIMIT 1
	)
	,points AS (
		SELECT PC_Explode(patch) as point
		FROM patch		
	)
	SELECT 
		--PC_Gets(point,'x','y','z','reflectance')
		row_number() over() as gid
		,PC_Get(point , 'x'::text ) AS x,  PC_Get(point , 'y'::text ) AS y,  PC_Get(point , 'z'::text ) AS z,  PC_Get(point  , 'reflectance'::text )  AS reflectance
		FROM points

	SELECT *
	FROM temp_toto_demo;

CREATE TABLE acquisition_tmob_012013.riegl_pcpatch_space_proxy
AS SELECT 
	gid
	, patch::geometry(polygon) AS geom
	, points_per_level
	,PC_NumPoints(patch) AS num_points
FROM acquisition_tmob_012013.riegl_pcpatch_space ;
	
	ALTER TABLE acquisition_tmob_012013.riegl_pcpatch_space_proxy ADD PRIMARY KEY (gid);
	CREATE INDEX ON acquisition_tmob_012013.riegl_pcpatch_space_proxy (gid);
	CREATE INDEX ON acquisition_tmob_012013.riegl_pcpatch_space_proxy USING GIST(geom);
	CREATE INDEX ON acquisition_tmob_012013.riegl_pcpatch_space_proxy USING GIN(points_per_level);
	CREATE INDEX ON acquisition_tmob_012013.riegl_pcpatch_space_proxy (num_points);

SELECT count(*)
FROM acquisition_tmob_012013.riegl_pcpatch_space_proxy
WHERE num_points BETWEEN 100 AND 10000
LIMIT 1;


SELECT *
FROM acquisition_tmob_012013.riegl_pcpatch_space_proxy as rps, def_zone_test as dzt
WHERE ST_DWITHIN(dzt.geom,rps.geom,0.1)=TRUE;


--getting about 500k points for demo
DROP TABLE IF EXISTS full_clustering_set;
CREATE TABLE full_clustering_set AS 
		WITH patch AS (	
		SELECT rps.*, PC_NUmPoints(patch) as num_points
		FROM acquisition_tmob_012013.riegl_pcpatch_space as rps , def_zone_test as dzt
		WHERE
			 PC_NUmPoints(patch) BETWEEN 100 AND 10000 
		AND
			ST_DWITHIN(dzt.geom,rps.patch::geometry,0.1)=TRUE   
	)
	,points AS (
		SELECT f.*, gid AS patch_gid, points_per_level, num_points, 1 AS has_lod
		FROM patch, rc_exploden_numbered(patch) as f
		WHERE points_per_level IS NOT NULL
		UNION ALL
		SELECT PC_Explode(patch) as point, 0 as ordinality , gid AS patch_gid,points_per_level,  num_points, 0 as has_lod
		FROM patch
		WHERE points_per_level IS NULL
	)
	SELECT 
		--PC_Gets(point,'x','y','z','reflectance')
		row_number() over() as gid
		,PC_Get(point , 'x'::text ) AS x,  PC_Get(point , 'y'::text ) AS y,  PC_Get(point , 'z'::text ) AS z,  PC_Get(point  , 'reflectance'::text )  AS reflectance
		,  patch_gid
		, num_points
		,has_lod
		,COALESCE(ordinality,-1) AS ordinality 
		, COALESCE(points_per_level[1], -1)AS lod0
		,COALESCE(points_per_level[2], -1) AS lod1
		,COALESCE(points_per_level[3], -1)AS lod2
		,COALESCE(points_per_level[4], -1) AS lod3
		, COALESCE(points_per_level[5], -1) AS lod4
		,  COALESCE(points_per_level[6], -1) AS lod5
		,  COALESCE(points_per_level[7], -1) AS lod6
		, COALESCE( points_per_level[8], -1) AS lod7
		, COALESCE( points_per_level[9], -1) AS lod8
		, COALESCE( points_per_level[10], -1) AS lod9 
		FROM points;

COPY full_clustering_set TO '/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/full_clustering_cloud.csv' WITH CSV HEADER;

--getting the same area, but this time usign the LOD feature to limit the number of points to max 1k per patch


DROP TABLE IF EXISTS reduced_clustering_set;
CREATE TABLE reduced_clustering_set AS 
	WITH patch AS (	
		SELECT rps.*, PC_NUmPoints(patch) as num_points
		FROM acquisition_tmob_012013.riegl_pcpatch_space as rps , def_zone_test as dzt
		WHERE
			 PC_NUmPoints(patch) BETWEEN 100 AND 10000 
		AND
			ST_DWITHIN(dzt.geom,rps.patch::geometry,0.1)=TRUE  
	)
	,points AS (
		SELECT f.*, gid AS patch_gid, points_per_level, num_points, 1 AS has_lod
		FROM patch, rc_exploden_numbered(patch,1000) as f
		WHERE points_per_level IS NOT NULL
		UNION ALL
		SELECT PC_Explode(patch) as point, 0 as ordinality , gid AS patch_gid,points_per_level,  num_points, 0 as has_lod
		FROM patch
		WHERE points_per_level IS NULL
	)
	SELECT 
		--PC_Gets(point,'x','y','z','reflectance')
		row_number() over() as gid
		,PC_Get(point , 'x'::text ) AS x,  PC_Get(point , 'y'::text ) AS y,  PC_Get(point , 'z'::text ) AS z,  PC_Get(point  , 'reflectance'::text )  AS reflectance
		,  patch_gid
		, num_points
		,has_lod
		,COALESCE(ordinality,-1) AS ordinality 
		, COALESCE(points_per_level[1], -1)AS lod0
		,COALESCE(points_per_level[2], -1) AS lod1
		,COALESCE(points_per_level[3], -1)AS lod2
		,COALESCE(points_per_level[4], -1) AS lod3
		, COALESCE(points_per_level[5], -1) AS lod4
		,  COALESCE(points_per_level[6], -1) AS lod5
		,  COALESCE(points_per_level[7], -1) AS lod6
		, COALESCE( points_per_level[8], -1) AS lod7
		, COALESCE( points_per_level[9], -1) AS lod8
		, COALESCE( points_per_level[10], -1) AS lod9 
		FROM points;


COPY reduced_clustering_set TO '/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/reduced_clustering_cloud.csv' WITH CSV HEADER;

