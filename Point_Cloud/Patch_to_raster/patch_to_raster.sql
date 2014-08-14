--Remi Cura Thales/IGN  10/03/2014
--Function to rasterize patch using postgis raster


-------------------------------------------------------------
--
--this scrip intend to try to use postgis raster functionnality with point_cloud functionnality
--the goal is to create raster out of point cloud patches.
--
--we use dependency functions 
-------------------------------------------------------------


SET search_path TO patch_to_raster,benchmark,public;
--SET client_min_messages TO WARNING;

----------------
--patch_to_raster
---------------


--------------
--function
--	patch2raster() : create a new raster out of a patch
--	rc_Patch2RasterBand() : add a band to a raster given a patch

	
	--DROP SCHEMA IF EXISTS patch_to_raster CASCADE;
	--CREATE SCHEMA patch_to_raster;
 
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
		-- ,FOREIGN KEY (rid) REFERENCES riegl_pcpatch_space (gid)
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

	SELECT AddRasterConstraints('rasterized_patch','rast');  

	SELECT ST_SUmmary(rast)
	FROM rasterized_patch ;

	--activate output for psotgis raster :
		SET postgis.enable_outdb_rasters TO 'ON';
		SET postgis.gdal_enabled_drivers TO 'ENABLE_ALL';
	--output the patches on the server : 
	SELECT write_file(ST_AsTIFF( rast ), '/tmp/rast_' || rid || '_2_2.tif','777'::character varying (4) )
	FROM  rasterized_patch ;

 

		--output only one patch(1816) with the Z information

		WITH patch  AS (
		SELECT rps.gid ,patch --, pc_NumPoints(patch) aS numpoints
		FROM riegl_pcpatch_space as rps
		--		INNER JOIN def_raster_qgis AS drq 
		--		ON (ST_Intersects(drq.geom,ST_SetSRID( patch::geometry ,932011) )  )
		WHERE gid = 1816
			--WHERE gid = 360004 --little patch
			--WHERE   ST_Area(ST_SetSRID(CAST(patch AS geometry ),932011))>0.8 
		),
		arr AS ( 
			--SELECT ARRAY ['patch_id,gps_time,x,y,z,x_origin,y_origin,z_origin,reflectance,range,theta,id,class,num_echo,nb_of_echo' ] AS dimensions
			SELECT ARRAY [ 'z' ] AS dimensions
		)
		 
			SELECT gid AS rid,   write_file(ST_AsTIFF( ST_SetSRID(  rc_Patch2Raster_arar(patch,dimensions ,0.05),932011 ) ),  '/tmp/rast_' || gid || '_Z_2.tif','777'::character varying (4) )
			FROM patch,arr;


	SELECT ST_GDALDrivers()



		--comapcting all the patches in the area into one, then outputting one raster.

			WITH patch  AS (
				SELECT 1 AS gid, PC_Union( patch ) AS patch--rps.gid ,patch --, pc_NumPoints(patch) aS numpoints
				FROM riegl_pcpatch_space as rps
					INNER JOIN def_raster_qgis AS drq 
					ON (ST_Intersects(drq.geom,ST_SetSRID( patch::geometry ,932011) )  )
				--WHERE gid = 361783   -- OR gid=361784 --big patch
				--WHERE gid = 360004 --little patch
				--WHERE   ST_Area(ST_SetSRID(CAST(patch AS geometry ),932011))>0.8 
				LIMIT 1 
			),
			arr AS ( 
				--SELECT ARRAY ['patch_id,gps_time,x,y,z,x_origin,y_origin,z_origin,reflectance,range,theta,id,class,num_echo,nb_of_echo' ] AS dimensions
				SELECT ARRAY ['gps_time','x','y','z','x_origin','y_origin','z_origin','reflectance','range','theta','id','class','num_echo','nb_of_echo' ] AS dimensions
				--SELECT ARRAY ['gps_time','x','y','z'] AS dimensions
			)
			--SELECT ST_SUmmary(rc_Patch2Raster_arar(patch,dimensions,0.05 ))
			--FROM patch,arr
			INSERT INTO rasterized_patch (rid, rast)
				SELECT gid AS rid,  ST_SetSRID( rc_Patch2Raster_arar(patch,dimensions,0.05 ),932011)  AS rast
				FROM patch,arr;
			--time : 		30sec for merging patches
			--			for creating temp table
			
	
 --testing interpolation
	--checking data
		SELECT rid, ST_Summary(rast) 
		FROM test_temp_raster

	DROP TABLE IF EXISTS temp_test_unioned_rast ;
	CREATE TABLE  temp_test_unioned_rast AS 
		SELECT 1 as rid, ST_Union(rast) AS rast
		FROM test_temp_raster;
	SELECT AddRasterConstraints('rasterized_patch','rast');  
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


  

 
--------------------------------
