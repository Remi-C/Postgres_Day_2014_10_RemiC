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

	  -- TABLE(support_points_indice INT[]  )  --, model float[])

	--a plpython function taking the array of double precision and printing what it understands of it
DROP FUNCTION IF EXISTS rc_py_point_array_to_numpy_array (iar FLOAT[]);
CREATE FUNCTION rc_py_point_array_to_numpy_array (iar FLOAT[] ) RETURNS TABLE( support_point_index int[] , model FLOAT[])   
AS $$

"""
this function demonstrate how to convert input float[] into a numpy array, then 
"""
import numpy as np ;
import pcl ; 
#plpy.notice(iar) ; 
#plpy.notice(type(iar)) ;

#converting the 1D array to 2D array
np_array = np.reshape(np.array(iar), (-1, 3)).astype(np.float32)  ; # note : we duplicate the data (copy), because we have to assume input data is read only
#np_array_float32 = np_array.astype(np.float32)
#plpy.notice(np_array) ; 
#plpy.notice(type(np_array)) ;



p = pcl.PointCloud() ;
p.from_array(np_array) ;

seg = p.make_segmenter_normals(ksearch=10)
seg.set_optimize_coefficients (True);
seg.set_model_type (pcl.SACMODEL_NORMAL_PLANE)
seg.set_normal_distance_weight (0.1)
seg.set_method_type (pcl.SAC_RANSAC)
seg.set_max_iterations (1000)
seg.set_distance_threshold (0.05)
indices, model = seg.segment()
#print model
cloud_plane = p.extract(indices, negative=False)

#plpy.notice('indices : ') ;
#plpy.notice(type(indices)) ;
#plpy.notice('model : ') ;
#plpy.notice(type(model)) ;
 
return [(indices,model)] ; #indices ; --,(model)); 
$$ LANGUAGE plpythonu;
	
	
	SELECT gid, PC_NumPoints(patch) AS npoints, result.*
	FROM riegl_pcpatch_space as rps,rc_patch_to_XYZ_array(patch) as arr , rc_py_point_array_to_numpy_array(arr) AS result
	WHERE --gid = 8480 
		--gid = 18875
		gid = 1598;
	
