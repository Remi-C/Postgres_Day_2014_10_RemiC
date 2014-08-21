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







 
	--a plpython function taking the array of double precision and converting it to pointcloud, then looking for a plane inside.
	--note that we could do the same to detect cylinder
DROP FUNCTION IF EXISTS rc_py_point_array_to_numpy_array ( FLOAT[],  INT,INT,  FLOAT,INT,FLOAT,INT);
CREATE FUNCTION rc_py_point_array_to_numpy_array (
	iar FLOAT[] 
	,min_support_points INT DEFAULT 4
	,max_plane_number INT DEFAULT 100
	,_distance_threshold FLOAT DEFAULT 0.1
	,_ksearch INT DEFAULT 50
	,_distance_weight FLOAT DEFAULT 0.5 --between 0 and 1 . 
	,_max_iterations INT DEFAULT 100 
	) 
RETURNS TABLE( support_point_index int[] , model FLOAT[], model_type TEXT)   
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
	    ,min_support_points
	    ,max_plane_number
	    , _ksearch
	    , pcl.SACMODEL_NORMAL_PLANE
	    , _distance_weight
	    , _max_iterations
	    , _distance_threshold) ;

plpy.notice(p_reduced.size) ;
#finding the cylinder in the cloud where planes points have been removed
cyl_result , p_reduced_2 = ptp.perform_N_ransac_segmentation(
	    p_reduced
	    , 5 #min_support_points
	    , 100 #max_plane_number
	    , 10 #_ksearch
	    , pcl.SACMODEL_CYLINDER
	    , 0.5 #_distance_weight
	    , 1000 #_max_iterations
	    , 0.1 # _distance_threshold
	    ) ; 

#result.append(  (cyl_result ) );   

for indices,model, model_type in cyl_result:
     if model != False:
	plpy.notice(model) ;
	result.append(( (indices),model,model_type ) ) ;  

return result ; 
$$ LANGUAGE plpythonu VOLATILE;
	
	--WITH the_results AS (
		SELECT gid, PC_NumPoints(patch) AS npoints
			--, result.*
			, result.support_point_index  as support_point_index
			,result.model AS model
			,result.model_type AS moedl_type
			--,count(*) OVer(PARTITION  BY support_point_index) as duplicate_point
		FROM riegl_pcpatch_space as rps,rc_patch_to_XYZ_array(patch) as arr 
			,   rc_py_point_array_to_numpy_array (
				iar :=arr 
				,min_support_points:=3
				,max_plane_number :=100
				,_distance_threshold:=0.01
				,_ksearch:=50
				,_distance_weight:=0.5
				,_max_iterations:=100
				) AS result
		WHERE -- gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			gid = 1740  --a patch with a cylinder?
		--ORDER BY support_point_index ASC
	--)
	--SELECT *
	--FROM the_results 
	--WHERE duplicate_point !=1
