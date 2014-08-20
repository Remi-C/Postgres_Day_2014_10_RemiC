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
RETURNS TABLE( support_point_index int[] , model FLOAT[])   
AS $$
"""
this function demonstrate how to convert input float[] into a numpy array
then importing it into a pointcloud (pcl)
then iteratively finding plan in the cloud using ransac
"""
import numpy as np ;
import pcl ; 

#converting the 1D array to 2D array
np_array = np.reshape(np.array(iar), (-1, 3)).astype(np.float32)  ; # note : we duplicate the data (copy), because we have to assume input data is read only

#importing this numpy array as pointcloud
p = pcl.PointCloud() ;
p.from_array(np_array) ;
i= 0 ;
result = list() ; 
stop_condition = False; 
indices = [0]*(min_support_points+1); 

while ((len(indices) >= min_support_points) & (i<=max_plane_number) & (p.size>=min_support_points)):   
	#prepare segmentation
	seg = p.make_segmenter_normals(ksearch=_ksearch)
	seg.set_optimize_coefficients (True);
	seg.set_model_type (pcl.SACMODEL_NORMAL_PLANE)
	seg.set_normal_distance_weight (_distance_weight) #Note : playing with this make the result more (0.5) or less(0.1) selective
	seg.set_method_type (pcl.SAC_RANSAC)
	seg.set_max_iterations (_max_iterations)
	seg.set_distance_threshold (_distance_threshold)
	#segment
	indices, model = seg.segment()   
	#writting result if it it satisfaying
	if(len(indices) >= min_support_points) :
		result.append(   (indices, model) ) ;
	#indices, model = seg.segment() 

	#prepare next iteration
	i+=1 ;
	p =  p.extract(indices, negative=True) ; #removing from the cloud the points already used for this plan
 
#print model
#remaining_points= p.extract(indices, negative=True)


#plpy.notice('indices : ') ;
#plpy.notice(type(indices[0])) ;
#plpy.notice('model : ') ;
#plpy.notice(type(model)) ;
return result ; #indices ; --,(model)); 
#return [(indices,model)] ; 
$$ LANGUAGE plpythonu;
	
	
	SELECT gid, PC_NumPoints(patch) AS npoints, result.*
	FROM riegl_pcpatch_space as rps,rc_patch_to_XYZ_array(patch) as arr , rc_py_point_array_to_numpy_array(arr,10,100,0.1) AS result
	WHERE --gid = 8480 
		--gid = 18875
		--gid = 1598;
		--gid = 1051; -- a patch half hozirontal, half vertical . COntain several plans
		gid = 1740 ; --a patch with a cylinder?