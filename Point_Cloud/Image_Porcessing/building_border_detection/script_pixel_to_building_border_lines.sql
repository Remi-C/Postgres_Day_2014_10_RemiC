-----------------------------------------------------------
--
--Rémi-C , Thales IGN
--04/2014
--
--This script convert point observation to lines
--
-----
--details
-----
---NOTE :  
--	the input are point constituing a line feature.
--	this is fuzzy logic : we estimate the size of spatial uncertainity for each point
--	we also estimate the size of missing detection uncertainity.

--warning : uses SFCGAL
-----------------------------------------------------------

--creating a schema to work in 
CREATE SCHEMA IF NOT EXISTS building_border_detection; 

--setting the search path
SET search_path TO building_border_detection, public; 

--load the raster converted to polygon


	CREATE TABLE border_pixel_as_polygon_clean  
	(
	  gid serial NOT NULL,
	  geom geometry(MultiPolygon,932011),
	  accum double precision,
	  CONSTRAINT border_pixel_as_polygon_clean_pkey PRIMARY KEY (gid)
	)

	CREATE INDEX ON border_pixel_as_polygon_clean USING GIST(geom);

	-- INSERT INTO border_pixel_as_polygon_clean (geom, accum)
	-- SELECT ST_SetSRID(geom,932011), dn
	-- FROM border_pixel_as_polygon

	DROP TABLE IF EXISTS border_pixel_as_polygon; 



--converting points to lines

	--input
	--CREATE TABLE fuzzy_area AS 
	--CREATE TABLE skeleton AS 
	DROP TABLE filtered_skeleton ;
	CREATE TABLE filtered_skeleton AS 
	
	WITH the_input_parameter AS (
		SELECT 0.1 AS spatial_fuzziness
			,0.5 AS building_fuzziness 
			LIMIT 1 
	)
	,input_points AS ( --getting the input point, plus making a confidence measure out of number of laser point per pixel
		SELECT gid, ST_Centroid(geom) AS pixel_center, accum/ (( SELECT max(accum) FROM border_pixel_as_polygon_clean) ) AS confidence
		FROM border_pixel_as_polygon_clean
		--LIMIT 100
	)
	,fuzzy_area AS (--we convert the point into fuzzy area.
		SELECT ST_Union(ST_Buffer(pixel_center,1.5*spatial_fuzziness , 'endcap=square')) AS fuzzy_areas
		FROM the_input_parameter,input_points
	)
	,dmped_fuzzy_area AS ( --we separate the multi geom into separate fuzzy area
		SELECT dmp_area.path  AS area_id,  ST_Simplify(dmp_area.geom,spatial_fuzziness/2) as fuzzy_area
		FROM the_input_parameter, fuzzy_area, ST_Dump(fuzzy_areas) AS dmp_area 
		)
	, confidence_per_area AS (--for each separated fuzzy area, we get the input_points that are in it, and sum the confidence of each. We also get the number of points inside
		SELECT 	sum(ip.confidence) AS sum_area_confidence  --sum(ip.confidence) OVER (partition BY fa.area_id) 
			,max(ip.confidence) AS max_area_confidence
			, count(*)  As points_in_area
			,area_id  
			--, fa.fuzzy_area
		FROM input_points AS ip --note : we can use inner join because we can guarantee that no point will be in 2 area. 
			, dmped_fuzzy_area AS fa 
			WHERE (ST_Intersects(fuzzy_area, pixel_center)=TRUE)	
		GROUP BY area_id
	)
	,area_with_confidence AS ( --we get together the geometry of the area and the confidence measure associated
		SELECT  df.fuzzy_area , cp.*
		FROM confidence_per_area AS cp 
			NATURAL JOIN dmped_fuzzy_area as df
	)  
	,skeleton_of_area AS ( --we use the straight skeleton
		SELECT  area_id, skeleton.path AS skeleton_id , skeleton.geom AS area_skeleton
		FROM area_with_confidence , ST_Dump(ST_StraightSkeleton(ST_MakePolygon(ST_ExteriorRing(fuzzy_area ))))  AS skeleton 
	)
	,removing_isolated_sskeleton_parts AS (--now we remove the lines of sskelton that have one of their endpoint not shared by another line
		SELECT sko1.*
		FROM the_input_parameter as tip ,skeleton_of_area AS sko1
			WHERE EXISTS (
				SELECT 1
				FROM skeleton_of_area AS sko2
				WHERE (sko1.area_id = sko2.area_id AND sko1.skeleton_id != sko2.skeleton_id) 
					AND (ST_DWithin(ST_EndPoint(sko2.area_skeleton),sko1.area_skeleton,tip.spatial_fuzziness )=TRUE
						AND ST_DWithin(ST_StartPoint(sko2.area_skeleton),sko1.area_skeleton,tip.spatial_fuzziness )=TRUE
					)
				)
	)
	 
	--,reducing_area AS (--we comput the reduced area to be able to filter the straight skeleton
	--	SELECT area_id, ST_Buffer(fuzzy_area,-spatial_fuzziness ) AS reduced_area
	--	FROM the_input_parameter, area_with_confidence
	--)
	--,filtering_skeleton AS (
	--	SELECT so.*
	--	FROM skeleton_of_area as so
	--		INNER JOIN reducing_area as ra ON (ra.area_id = so.area_id AND ST_Within(so.area_skeleton,ra.reduced_area)=TRUE )
	--)
	SELECT row_number() over() AS qgis_id, fs.area_id --, fs.skeleton_id
		, ST_Simplify(ST_Union(fs.area_skeleton),building_fuzziness ) AS area_skeleton
		,max(aw.sum_area_confidence ) AS sum_area_confidence
		,max(aw.max_area_confidence ) AS max_area_confidence
		,max(aw.points_in_area ) AS  points_in_area
	FROM the_input_parameter , removing_isolated_sskeleton_parts as fs
		LEFT OUTER JOIN area_with_confidence AS aw ON (fs.area_id = aw.area_id)
	GROUP BY fs.area_id, the_input_parameter.building_fuzziness

	 


	 


	WITH area_with_confidence AS (
		SELECT ST_Astext(ST_SnapToGrid(fuzzy_area,0.01) ) AS snapped, *  
		FROM area_with_confidence
		WHERE area_id[1] = 39
	) 
	SELECT ST_AsText(ST_StraightSkeleton( snapped  ))
	FROM area_with_confidence


	--

	SELECT ST_AsText(ST_StraightSkeleton(geom))
	FROM ST_GeomFromText('POLYGON((1914.52 21143.76,1914.52 21143.46,1914.22 21143.46,1914.22 21143.76,1914.12 21143.76,1914.12 21144.46,1914.42 21144.46,1914.42 21143.76,1914.52 21143.76))') as geom