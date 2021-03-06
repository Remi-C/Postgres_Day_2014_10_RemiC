﻿-----------------------------------------------------------
--
--Rémi-C , Thales IGN
--08/2014
--
--This script create function to analyse structure of points in a patch
--
-----
---
--
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

	 
	--a plpython function taking the array of double precision and converting it to pointcloud, then looking for planes inside, then cylinder
	--note that we could do the same to detect cylinder
DROP FUNCTION IF EXISTS rc_py_pca_and_ica ( FLOAT[] );
CREATE FUNCTION rc_py_pca_and_ica (
	iar FLOAT[]  
	) 
RETURNS TABLE( norm FLOAT,structural_vector float[])--, structural_vector float[]) 
AS $$
""" 
	This function perform PCA/ICA and others to demonstrates analysis of structure of a vector of points(3D, but could be 2D)
	it returns 3 vectors, along with the norm of each vector.
	The vector are the directions that explain best the data.
"""
#importing needed modules
import plpy ;
import numpy as np ;   
from sklearn.decomposition import FastICA; 

#converting the 1D array to 2D array (vector of 3D points)
np_array = np.reshape(np.array(iar), (-1, 3)); 
np_array-=np.nanmax(np_array, axis=0) ;
#performing ICA on the numpy array
ica = FastICA(n_components=20
	, algorithm='parallel'
	, whiten=True
	, fun='logcosh' 
	, max_iter=200
	, tol=0.0001  ) ;
ica.fit(np_array) ;

#normalizing the result
norms =  np.linalg.norm(ica.mixing_,None,1) ;
normalized_result = ica.mixing_ / norms[:, np.newaxis] ;

result = list() ; 
for i in range(0,3):
	result.append(( norms[i],(normalized_result[i]) ) ) ;  
 
return result  ; 
$$ LANGUAGE plpythonu IMMUTABLE STRICT; 

	 -- testing querry  :
		SELECT gid, PC_NumPoints(patch) AS npoints , result.* 
		FROM riegl_pcpatch_space as rps
			,rc_patch_to_XYZ_array(patch) as arr 
			,   rc_py_pca_and_ica (
				iar := arr
				 ) AS result
		WHERE  
			--gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			gid = 1740 ; --a patch with a cylinder?  
	 

	--new function to be able to visualize the result in cloudcompare :
	--we will materialize the vector by creating points all along. This way we can see something.
	DROP FUNCTION IF EXISTS rc_patch_to_structural_vector_points(ipatch PCPATCH, i_patch_id INT);
	CREATE OR REPLACE FUNCTION rc_patch_to_structural_vector_points(ipatch PCPATCH, i_patch_id INT )
	  RETURNS TABLE  (X DOUBLE PRECISION,Y DOUBLE PRECISION , Z DOUBLE PRECISION
		, patch_id INT, vector_id int, norm FLOAT)
	  AS
	$BODY$
			--@brief this perform a ICA computing, then creates points along the dected vectors and output suitable data for visu in cloud comapre
			-- @return :  a table holding the points along the vector with identification information
			DECLARE 
			BEGIN 

			RETURN QUERY 
			WITH ICA_result AS (	
				SELECT i_patch_id AS patch_id
					, ST_X(centroid) AS X_center, ST_Y(centroid) AS Y_center, (upper(z_int)+lower(z_int))/2 AS Z_center
					,(row_number() over())::int AS vector_id
					,   result.* 
				FROM  (SELECT ipatch as pa) as pa,ST_Centroid( pa::geometry) as centroid
				,rc_compute_range_for_a_patch( pa ,'Z') as z_int
				,rc_patch_to_XYZ_array( pa) as arr 
				,   rc_py_pca_and_ica (
					iar := arr
					 ) AS result 
			)
			--,generating_the_points AS (

				SELECT round((X_center + structural_vector[1] * generate_series(1,100)* round(ica.norm::numeric,2)/1000)::numeric,3)::float AS X  
					,round((Y_center + structural_vector[2] * generate_series(1,100)* round(ica.norm::numeric,2)/1000)::numeric,3)::float AS Y
					,round((Z_center + structural_vector[3] * generate_series(1,100)* round(ica.norm::numeric,2)/1000 )::numeric,3)::float AS Z
					,ica.patch_id
					, ica.vector_id
					,ica.norm
				FROM ICA_result AS ica ;
			
		 
				RETURN; 
			END ; 
		$BODY$
	LANGUAGE plpgsql IMMUTABLE STRICT;
	--SELECT rc_patch_to_XYZ_array()

	--testing
-- 	SELECT result.*
-- 	FROM riegl_pcpatch_space as rps
-- 		,rc_patch_to_structural_vector_points(rps.patch, rps.gid) AS result
-- 	WHERE gid = 1051; --1740	;


	COPY 
		( 
			SELECT result.*
	FROM riegl_pcpatch_space as rps
		,rc_patch_to_structural_vector_points(rps.patch, rps.gid) AS result
	WHERE 
		--gid = 8480 
		--gid = 18875 -- very small patch
		--gid = 1598 
		gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
		--gid = 1740   --a patch with a cylinder?  
		)
	TO '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Patch_to_python/data/structural_vector_sidewalk_wall.csv'-- '/tmp/temp_pointcloud.csv'
	WITH csv header;