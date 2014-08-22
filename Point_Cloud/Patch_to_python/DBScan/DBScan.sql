-----------------------------------------------------------
--
--Rémi-C , Thales IGN
--08/2014
--
--This script create function to perform DBScan clustering on input 2D point cloud
-- 
--warning : uses PLPYTHON
-----------------------------------------------------------

 
--setting the search path
SET search_path TO patch_to_python, benchmark, public; 


--getting some patch to wok on 
	SELECT gid, PC_NumPoints(patch) AS npoints--, pt.ordinality, pt.point
	FROM riegl_pcpatch_space as rps--, public.rc_ExplodeN_numbered( patch , 10) AS pt
	WHERE ST_DWithin(rps.patch::geometry, ST_MakePoint(1899.56,21226.90),0.1)=TRUE
	ORDER BY npoints ASC ;

	--we work on patch 8480 for example, with 2269 points 
 
 

 
	--a plpython function taking the array of double precision and converting it to pointcloud, then looking for planes inside, then cylinder
	--note that we could do the same to detect cylinder
DROP FUNCTION IF EXISTS rc_py_dbscan ( FLOAT[],data_dim INT, eps float, min_samples float);
CREATE FUNCTION rc_py_dbscan (
	iar FLOAT[] 
	,data_dim INT DEFAULT 3
	, eps float DEFAULT 0.01
	, min_samples float DEFAULT 10
	) 
RETURNS FLOAT[] 
AS $$
"""
this function demonstrate how to convert input float[] into a numpy array
the entry is expected to be of 4D Points (X,Y,Z,reflectance)
then we perform DBSCAN on it. 
"""
#importing neede modules
import plpy;
import numpy as np ;
from sklearn.cluster import DBSCAN ; 


#converting from 1D list to 2D numpy array (array of 4D points)
np_array = np.reshape(np.array(iar), (-1, data_dim)); 
np_array-=np.nanmax(np_array, axis=0) ; 


#performing clustering 
db = DBSCAN(eps, min_samples).fit(np_array) ;
core_samples_mask = np.zeros_like(db.labels_, dtype=bool) ;
core_samples_mask[db.core_sample_indices_] = True ;
labels = db.labels_ ;

#plpy.notice(core_samples_mask) ;
#plpy.notice(labels.size) ;

return labels; 

$$ LANGUAGE plpythonu IMMUTABLE STRICT; 
 
 	
	WITH  points AS (
			SELECT gid,pt.ordinality::int, pt.point AS point  
			FROM  riegl_pcpatch_space as rps, public.rc_ExplodeN_numbered(patch) as pt 
			WHERE  
			--gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			--gid = 1740 --a patch with a cylinder?  
		)
		,points_coordinate_ad_float_arr AS (
			SELECT array_agg_custom(
					ARRAY[
						PC_Get(pt.point,'X')::DOUBLE PRECISION
						, PC_Get(pt.point,'Y')::DOUBLE PRECISION
						, PC_Get(pt.point,'Z')::DOUBLE PRECISION
						, PC_Get(pt.point,'reflectance')::float/50.0
					] ORDER BY pt.ordinality ASC ) as arr
			FROM points as pt
		)
		,segmented_indices AS (---get the indexes of points resulting from segmentation
			SELECT  (row_number() over())::int AS feature_id,result.*  
			FROM points_coordinate_ad_float_arr as float_arr
				,   rc_py_dbscan ( iar := float_arr.arr  
					,data_dim :=4
					,eps := 0.1
					,min_samples := 50) AS result
		)
		,unnested_indices AS(
			SELECT unnest(result)
			FROM segmented_indices
		)
		SELECT DISTINCT *
		FROM unnested_indices;
	 