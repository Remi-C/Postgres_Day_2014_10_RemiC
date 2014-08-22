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
DROP FUNCTION IF EXISTS rc_py_dbscan ( FLOAT[]);
CREATE FUNCTION rc_py_dbscan (
	iar FLOAT[] 
	 
	) 
RETURNS BOOLEAN 
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
np_array = np.reshape(np.array(iar), (-1, 4)); 
np_array-=np.nanmax(np_array, axis=0) ; 


#perfomring clustering 
db = DBSCAN(eps=0.3, min_samples=10).fit(np_array) ;
core_samples_mask = np.zeros_like(db.labels_, dtype=bool) ;
core_samples_mask[db.core_sample_indices_] = True ;
labels = db.labels_ ;

plpy.notice(labels) ;

return True; 

$$ LANGUAGE plpythonu IMMUTABLE STRICT; 

 
	WITH  points AS (
			SELECT pt.ordinality::int, pt.point AS point  
			FROM  public.rc_ExplodeN_numbered(ipatch) as pt 
		)
		,points_coordinate_ad_float_arr AS (
			SELECT array_agg_custom(
					ARRAY[
						PC_Get(pt.point,'X')::float 
						, PC_Get(pt.point,'Y')::float 
						, PC_Get(pt.point,'Z')::float
						, PC_Get(pt.point,'reflectance')::float] 
					ORDER BY pt.ordinality ASC ) as arr
			FROM points as pt
		)
		,segmented_indices AS (---get the indexes of points resulting from segmentation
			SELECT  (row_number() over())::int AS feature_id,result.*  
			FROM points_coordinate_ad_float_arr as float_arr
				,   rc_py_dbscan ( iar := float_arr.arr  ) AS result ;
	 
