--Remi Cura Thales/IGN  10/03/2014
--Function to rasterize patch using postgis raster


-------------------------------------------------------------
--
--this scrip intend to try to use postgis raster functionnality with point_cloud functionnality
--the goal is to create raster out of point cloud patches.
--
--we use dependency functions 
-------------------------------------------------------------

DROP SCHEMA IF EXISTS patch_to_raster CASCADE;
CREATE SCHEMA patch_to_raster;

SET search_path TO patch_to_raster,benchmark,public;
--SET client_min_messages TO WARNING;

----------------
--patch_to_raster
---------------


--------------
--function
--	patch2raster() : create a new raster out of a patch
--	rc_Patch2RasterBand() : add a band to a raster given a patch

	
 
-- create a polygon tabel to define where we want to convert patch to raster 

	DROP TABLE IF EXISTS def_raster_qgis; 
	CREATE TABLE def_raster_qgis (
		gid SERIAL PRIMARY KEY
		,geom GEOMETRY(polygon, 932011)
	);
	CREATE INDEX ON def_raster_qgis USING GIST(geom) ;

	--SELECT ST_AsText(geom)
	--FROM def_raster_qgis;

	INSERT INTO def_raster_qgis 
		VALUES (1
			,ST_GeomFromText('POLYGON((1902.64693747078 21169.250942804,1908.7664853937 21169.7987625962,1909.15396768576 21165.0688063414,1902.75382913756 21165.3761198833,1902.64693747078 21169.250942804))'
				,932011)
			);

--now, convert every patch in the def_raster_qgis to a raster

	--create a raster table to hold result : 
	
	DROP TABLE IF EXISTS rasterized_patch;
	CREATE TABLE rasterized_patch (
		rid INT PRIMARY KEY
		,rast   raster
		 ,FOREIGN KEY (rid) REFERENCES riegl_pcpatch_space (gid)
	);
	TRUNCATE rasterized_patch ;


	--get all patch in the defined area
	WITH patch  AS (
		SELECT rps.gid ,patch --, pc_NumPoints(patch) aS numpoints
		FROM riegl_pcpatch_space as rps
			INNER JOIN def_raster_qgis AS drq 
			ON (ST_Intersects(drq.geom,ST_SetSRID( patch::geometry ,932011) )  )
		--WHERE gid = 361783   -- OR gid=361784 --big patch
		--WHERE gid = 360004 --little patch
		--WHERE   ST_Area(ST_SetSRID(CAST(patch AS geometry ),932011))>0.8 
	),
	arr AS ( 
		--SELECT ARRAY ['patch_id,gps_time,x,y,z,x_origin,y_origin,z_origin,reflectance,range,theta,id,class,num_echo,nb_of_echo' ] AS dimensions
		SELECT ARRAY ['gps_time','x','y','z','x_origin','y_origin','z_origin','reflectance','range','theta','id','class','num_echo','nb_of_echo' ] AS dimensions
	)
	INSERT INTO rasterized_patch (rid, rast)
		SELECT gid AS rid,  ST_SetSRID( ST_Transform(rc_Patch2Raster_arar(patch,dimensions ),932011),932011)  AS rast
		FROM patch,arr;

	SELECT AddRasterConstraints('test_temp_raster','rast');  


		SELECT rps.gid,pc_AsText(patch)
		FROM acquisition_tmob_012013.riegl_pcpatch_space as rps 
		 WHERE  gid=240 --big patch

		SELECT gid, PC_NUmPoints(patch)
		FROM acquisition_tmob_012013.riegl_pcpatch_space as rps
		WHERE PC_NumPoints(patch)>100000
		LIMIT 1
--testing interpolation
	--checking data
		SELECT rid, ST_Summary(rast) 
		FROM test_temp_raster

	DROP TABLE IF EXISTS temp_test_unioned_rast ;
	CREATE TABLE  temp_test_unioned_rast AS 
		SELECT 1 as rid, ST_Union(rast) AS rast
		FROM test_temp_raster;
	SELECT AddRasterConstraints('temp_test_unioned_rast','rast');  
	--interpolation
	DROP TABLE IF EXISTS temp_test_interpolation;
	CREATE TABLE temp_test_interpolation AS 
	SELECT  rid, ST_MapAlgebra(
		rast
		, ARRAY[1,2,3,4,5,6,7,8,9,10,11,12 ,13]
		, 'ST_Mean4ma(double precision[] , integer[], text[])'::regprocedure     
		,NULL
		,'FIRST'
		,rast
		,2::integer
		,2::integer 
		) AS rast
	FROM test_temp_raster 
	--WHERE rid = 361783

	SELECT ST_Summarystats(rast)
	FROM temp_test_interpolation
	
	
	SELECT ST_MapAlgebra(
		rast, ARRAY[3, 1, 3, 2]::integer[],
		'ST_InvDistWeight4ma(double precision[], int[], text[])'::regprocedure)
		FROM test_temp_raster
	-- st_mapalgebra(rast := raster, nband := integer[], callbackfunc := regprocedure, pixeltype := text, extenttype := text, customextent := raster, distancex := integer, distancey := integer, userargs := text[]) does not exist

	-- st_mapalgebra(IN rast raster, IN nband integer[], IN callbackfunc regprocedure, IN pixeltype text DEFAULT NULL::text, IN extenttype text DEFAULT 'FIRST'::text, IN customextent raster DEFAULT NULL::raster, IN distancex integer DEFAULT 0, IN distancey integer DEFAULT 0, VARIADIC userargs text[] DEFAULT NULL::text[])


  

 



