-----------------------------------------------------------
--
--Rémi-C , Thales IGN
--08/2014
--
--This script create function to convert from pointcloud pcpatch to numpy array, suitable for data processing in python
--
-----
--details
-----
---NOTE :  
--	the input are point constituing a line feature.
--	this is fuzzy logic : we estimate the size of spatial uncertainity for each point
--	we also estimate the size of missing detection uncertainity.

--warning : uses PLPYTHON
-----------------------------------------------------------



CREATE SCHEMA IF NOT EXISTS patch_to_python; 

--setting the search path
SET search_path TO patch_to_python, benchmark, public; 


--getting some patch to wok on 
	SELECT gid, PC_NumPoints(patch) AS npoints--, pt.ordinality, pt.point
	FROM riegl_pcpatch_space as rps--, public.rc_ExplodeN_numbered( patch , 10) AS pt
	WHERE ST_DWithin(rps.patch::geometry, ST_MakePoint(1899.56,21226.90),0.1)=TRUE
	ORDER BY npoints ASC ;

	--we work on patch 8480 for example, with 2269 points 

--creating a function to convert patch points into array of [X Y Z ]

	--we need an array agg for array, found in PPPP_utilities
			DROP AGGREGATE public.array_agg_custom(anyarray) ;
			CREATE AGGREGATE public.array_agg_custom(anyarray)
				( SFUNC = array_cat,
				STYPE = anyarray
				);

	--a wrapper function to convert from patch to array[array[]], so to be able to transmit information	
	DROP FUNCTION IF EXISTS rc_patch_to_XYZ_array(ipatch PCPATCH,maxpoints INT);
	CREATE OR REPLACE FUNCTION rc_patch_to_XYZ_array(ipatch PCPATCH,maxpoints INT DEFAULT 0
		)
	  RETURNS FLOAT[] AS
	$BODY$
			--@brief this function clean result tables
			-- @return :  nothing 
			DECLARE 
			BEGIN 
				RETURN array_agg_custom(ARRAY[PC_Get(pt.point,'X')::float , PC_Get(pt.point,'Y')::float , PC_Get(pt.point,'Z')::float] ORDER BY pt.ordinality ASC )
				FROM public.rc_ExplodeN_numbered(  ipatch,maxpoints) as pt ;
				 
				--RETURN NULL;
			END ; 
		$BODY$
	LANGUAGE plpgsql IMMUTABLE STRICT;
	--SELECT rc_patch_to_XYZ_array()

	SELECT gid, PC_NumPoints(patch) AS npoints , rc_patch_to_XYZ_array(patch) as result
	FROM riegl_pcpatch_space as rps
	WHERE --gid = 8480 --verticla patch
		gid = 18875; --small patch 







 
	--a plpython function taking the array of double precision and converting it to pointcloud, then looking for planes inside, then cylinder
	--note that we could do the same to detect cylinder
DROP FUNCTION IF EXISTS rc_py_plane_and_cylinder_detection ( FLOAT[],  INT,INT,  FLOAT,INT,FLOAT,INT,  INT,INT,  FLOAT,INT,FLOAT,INT);
CREATE FUNCTION rc_py_plane_and_cylinder_detection (
	iar FLOAT[] 
	,plane_min_support_points INT DEFAULT 4
	,plane_max_number INT DEFAULT 100
	,plane_distance_threshold FLOAT DEFAULT 0.1
	,plane_ksearch INT DEFAULT 50
	,plane_distance_weight FLOAT DEFAULT 0.5 --between 0 and 1 . 
	,plane_max_iterations INT DEFAULT 100 

	,cyl_min_support_points INT DEFAULT 7
	,cyl_max_number INT DEFAULT 100
	,cyl_distance_threshold FLOAT DEFAULT 0.1
	,cyl_ksearch INT DEFAULT 10
	,cyl_distance_weight FLOAT DEFAULT 0.5 --between 0 and 1 . 
	,cyl_max_iterations INT DEFAULT 100 
	) 
RETURNS TABLE( support_point_index int[] , model FLOAT[], model_type INT)   
AS $$
"""
this function demonstrate how to convert input float[] into a numpy array
then importing it into a pointcloud (pcl)
then iteratively finding plan in the cloud using ransac
	find a plan and points in it. 
	remove thoses points from the cloud
	keep their number
	iterate
	note :about index_array. the problem is each time we perform segmentation we get indices of points in plane. The problem is when the cloud has changed, this indices in the indices  of points in the new cloud and not indices of points in the original cloud. 
	We use therefore index_array to keep the information of orginal position in original cloud. We change it along to adapt to removal of points.
"""
#importing neede modules
import numpy as np ;
import pcl ; 
import pointcloud_to_pcl as ptp; #this one is a helper module to lessen duplicates of code
reload(ptp) ;

#converting the 1D array to pcl pointcloud 
p = ptp.list_of_point_to_pcl(iar) ;

#finding the plane 
result , p_reduced = ptp.perform_N_ransac_segmentation(
	    p
	    ,plane_min_support_points
	    ,plane_max_number
	    , plane_ksearch
	    , pcl.SACMODEL_NORMAL_PLANE
	    , plane_distance_weight
	    , plane_max_iterations
	    , plane_distance_threshold) ;

#finding the cylinder in the cloud where planes points have been removed
cyl_result , p_reduced_2 = ptp.perform_N_ransac_segmentation(
	    p_reduced
	    , cyl_min_support_points
	    , cyl_max_number
	    , cyl_ksearch
	    , pcl.SACMODEL_CYLINDER
	    , cyl_distance_weight
	    , cyl_max_iterations
	    , cyl_distance_threshold
	    ) ; 

#result.append(  (cyl_result ) );   

for indices,model, model_type in cyl_result:
     if model != False:
	result.append(( (indices),model,model_type ) ) ;  

return result ; 
$$ LANGUAGE plpythonu IMMUTABLE STRICT;
	
	/* testing querry  :
		SELECT gid, PC_NumPoints(patch) AS npoints
			--, result.*
			, result.support_point_index  as support_point_index
			,result.model AS model
			,result.model_type AS moedl_type
			--,count(*) OVer(PARTITION  BY support_point_index) as duplicate_point
		FROM riegl_pcpatch_space as rps,rc_patch_to_XYZ_array(patch) as arr 
			,   rc_py_plane_and_cylinder_detection (
				iar := arr
				,plane_min_support_points :=10
				,plane_max_number:=20
				,plane_distance_threshold:=0.01
				,plane_ksearch :=50
				,plane_distance_weight:=0.5 --between 0 and 1 . 
				,plane_max_iterations:=100 

				,cyl_min_support_points:=20
				,cyl_max_number:=100
				,cyl_distance_threshold:=0.05
				,cyl_ksearch:=10
				,cyl_distance_weight:=0.5 --between 0 and 1 . 
				,cyl_max_iterations:=100   
				) AS result
		WHERE -- gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			gid = 1740  --a patch with a cylinder?
	*/


	--a utility function that will take a patch and ouput rows of pointcloud data suitable for exporting :

	DROP FUNCTION IF EXISTS rc_patch_to_plane_and_cylinder_points(ipatch PCPATCH);
	CREATE OR REPLACE FUNCTION rc_patch_to_plane_and_cylinder_points(ipatch PCPATCH
		)
	  RETURNS TABLE (X float,Y float , Z float, index INT, patch_id INT, feature_id int, feature_type int)
	  AS
	$BODY$
			--@brief this perform plane and cylinder detection and returns the points being in those planes and cylinders
			-- @return :  a table holding the informations needed to identify backward who belongs where
			DECLARE 
			BEGIN 

			WITH patch_id AS (
				SELECT 1740 AS patch_id --a patch with a cylinder?
					--1051 -- a patch half hozirontal, half vertical . COntain several plans
			)
			, points AS (
				SELECT pt.ordinality, pt.point AS point  
				FROM patch_id, riegl_pcpatch_space as rps, public.rc_ExplodeN_numbered(rps.patch) as pt
				WHERE 
					--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
					gid = patch_id  --a patch with a cylinder?
			)
			,points_coordinate_ad_float_arr AS (
				SELECT array_agg_custom(ARRAY[PC_Get(pt.point,'X')::float , PC_Get(pt.point,'Y')::float , PC_Get(pt.point,'Z')::float] ORDER BY pt.ordinality ASC ) as arr
				FROM points as pt
			)
			,segmented_indices AS (---get the indexes of points resulting from segmentation
				SELECT  row_number() over() AS feature_id,result.*  
				FROM points_coordinate_ad_float_arr as float_arr
					,   rc_py_plane_and_cylinder_detection (
						iar := float_arr.arr
						,plane_min_support_points :=10
						,plane_max_number:=20
						,plane_distance_threshold:=0.01
						,plane_ksearch :=50
						,plane_distance_weight:=0.5 --between 0 and 1 . 
						,plane_max_iterations:=100  
						,cyl_min_support_points:=20
						,cyl_max_number:=100
						,cyl_distance_threshold:=0.05
						,cyl_ksearch:=10
						,cyl_distance_weight:=0.5 --between 0 and 1 . 
						,cyl_max_iterations:=100   
						) AS result 
			)
			,unnested_indices AS (
				SELECT feature_id, unnest(support_point_index) AS indices
				FROM segmented_indices
			)
			--,segmented_points AS (
				SELECT PC_Get(pt.point,'X')::float AS X, PC_Get(pt.point,'Y')::float AS Y, PC_Get(pt.point,'Z')::float AS Z
					,pt.ordinality AS index
					,patch_id
					,si.feature_id
					,si.model_type AS feature_type
					,model_coef
					,model_coef[1] AS Nx
					,model_coef[2] AS Ny
					,model_coef[3] AS Nz
					,model_coef[4] as radius
				FROM patch_id, points as pt
					INNER JOIN unnested_indices AS ui ON (pt.ordinality = ui.indices)
					INNER JOIN segmented_indices AS si ON (ui.feature_id = si.feature_id)
					,LATERAL (SELECT CASE WHEN model_type = 11 --plane
						THEN
							ARRAY[model[1],model[2],model[3],0.0]
						WHEN model_type = 5 --cylinder
						THEN 
							ARRAY[model[4],model[5],model[6],model[7]]
						END AS model_coef)  AS model_coef 
			)	 
			
				RETURN; 
			END ; 
		$BODY$
	LANGUAGE plpgsql IMMUTABLE STRICT;
	--SELECT rc_patch_to_XYZ_array()
 
	--performing planes and cylinders detection on patches and exporting it to file system to be browsed with CloudCompare Software.
	COPY 
		( 
		SELECT ST_X(point) AS X, ST_Y(point) AS Y,ST_Z(point) AS Z, gid
		FROM (
			SELECT PC_Explode(patch )::geometry As  point, gid
			FROM acquisition_tmob_012013.riegl_pcpatch_space 
			WHERE PC_NumPoints(patch)>85
				AND gid >= 369310 AND gid < 372838
				AND points_per_level IS NOT NULL
			) AS toto
			--LIMIT 1
		)
	TO '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Patch_to_python/data/plane_and_cylinder_detection.csv'-- '/tmp/temp_pointcloud.csv'
	WITH csv header;
	
