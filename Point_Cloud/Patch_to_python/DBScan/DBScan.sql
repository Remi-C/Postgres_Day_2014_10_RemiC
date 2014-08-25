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
	,OUT cluster_id INT[]
	,OUT is_core BOOLEAN[]
	)  
AS $$
"""
this function demonstrate how to convert input float[] into a numpy array
the entry is expected to be of 4D Points (X,Y,Z,reflectance)
then we perform DBSCAN on it. 
"""
#importing neede modules
import plpy;
import numpy as np ;
import pcl;
from sklearn.cluster import DBSCAN ; 
reload(pcl);


#converting from 1D list to 2D numpy array (array of 4D points)
np_array = np.reshape(np.array(iar), (-1, data_dim)); 
np_array-=np.nanmax(np_array, axis=0) ; 

#creating a point cloud to compute normals
#reshaping the numpy array to keep only X, Y , Z
geom_array  = np_array[:,0:3 ].astype(np.float32) ;
	#plpy.notice(geom_array) ;
#creating a point cloud with this array of points
p = pcl.PointCloud() ;
p.from_array( geom_array) ;
#computing the normal of the point clouds :  
normals = p.calc_normals(-1,0.1);
	#plpy.notice(normals) ; 
#project normals on Z vector with a scalar product : this give a score between 0 and 1 of how much the normal is vertical
verticality = 1-abs(np.dot(normals,[0,0,1])); 
	#plpy.notice(normals); 

	#plpy.notice(geom_array.shape);
	#plpy.notice((normals).shape);
#adding the verticality score to input array :
geom_array = np.concatenate((geom_array, verticality[:,np.newaxis]), axis=1); 
	#plpy.notice(geom_array); 
#performing clustering 
db = DBSCAN(eps, min_samples).fit(geom_array) ;
core_samples_mask = np.zeros_like(db.labels_, dtype=bool) ;
core_samples_mask[db.core_sample_indices_] = True ;
labels = db.labels_ ;
#plpy.notice(labels.dtype) ;
#plpy.notice(core_samples_mask) ;
#plpy.notice(labels.size) ;

return ((labels.astype(np.int32)) , (core_samples_mask.astype(np.bool)) ); #converting from double to int32

$$ LANGUAGE plpythonu IMMUTABLE STRICT; 
 
 -- 	--testing
-- 		WITH  points AS (
-- 			SELECT gid,pt.ordinality::int, pt.point AS point  
-- 			FROM  riegl_pcpatch_space as rps, public.rc_ExplodeN_numbered(patch) as pt 
-- 			WHERE  
-- 			--gid = 8480 
-- 			--gid = 18875 -- very small patch
-- 			--gid = 1598 
-- 			gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
-- 			--gid = 1740 --a patch with a cylinder?  
-- 		)
-- 		,points_coordinate_ad_float_arr AS (
-- 			SELECT array_agg_custom(
-- 					ARRAY[
-- 						PC_Get(pt.point,'X')::DOUBLE PRECISION
-- 						, PC_Get(pt.point,'Y')::DOUBLE PRECISION
-- 						, PC_Get(pt.point,'Z')::DOUBLE PRECISION
-- 						, PC_Get(pt.point,'reflectance')::float/50.0
-- 					] ORDER BY pt.ordinality ASC ) as arr
-- 			FROM points as pt
-- 		)
-- 		--,segmented_indices AS (---get the indexes of points resulting from segmentation
-- 			SELECT  (row_number() over())::int AS feature_id,result.*  
-- 			FROM points_coordinate_ad_float_arr as float_arr
-- 				,   rc_py_dbscan ( iar := float_arr.arr  
-- 					,data_dim :=4
-- 					,eps := 0.1
-- 					,min_samples := 50) AS result
-- 		)
-- 		,unnested_indices AS(
-- 			SELECT unnest(result)
-- 			FROM segmented_indices
-- 		)
-- 		SELECT DISTINCT *
-- 		FROM unnested_indices;

	/*
		--a utility function that will take a patch and ouput rows of pointcloud data suitable for exporting :
	DROP FUNCTION IF EXISTS rc_patch_DBScan_clustering_points(ipatch PCPATCH, patch_id INT, FLOAT,INT );
	CREATE OR REPLACE FUNCTION rc_patch_DBScan_clustering_points(ipatch PCPATCH, i_patch_id INT,_eps FLOAT DEFAULT 0.1, _min_samples INT  DEFAULT 10)
	  RETURNS TABLE (X DOUBLE PRECISION,Y DOUBLE PRECISION , Z DOUBLE PRECISION, reflectance DOUBLE PRECISION
		, index INT
		, patch_id INT, cluster_id int, is_core INT)
	  AS
	$BODY$
		--@brief this perform plane and cylinder detection and returns the points being in those planes and cylinders
		-- @return :  a table holding the informations needed to identify backward who belongs where
		DECLARE 
		BEGIN 

			RETURN QUERY 
 
			WITH  points AS (
				SELECT pt.ordinality::int, pt.point AS point  
				FROM  public.rc_ExplodeN_numbered(ipatch) as pt  
			)
			,points_coordinate_ad_float_arr AS (
				SELECT array_agg_custom(
						ARRAY[
							PC_Get(pt.point,'X')::DOUBLE PRECISION
							, PC_Get(pt.point,'Y')::DOUBLE PRECISION
							, PC_Get(pt.point,'Z')::DOUBLE PRECISION
							, PC_Get(pt.point,'reflectance')::float/10.0
						] ORDER BY pt.ordinality ASC ) as arr
				FROM points as pt
			)
			,segmented_indices AS (---get the indexes of points resulting from segmentation
				SELECT result.*  
				FROM points_coordinate_ad_float_arr as float_arr
					,   rc_py_dbscan ( iar := float_arr.arr  
						,data_dim :=4
						,eps := _eps
						,min_samples := _min_samples) AS result
			)
			,unnested_cluster_id AS(
				SELECT indices.ordinality, indices.value AS cluster_id
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.cluster_id) as indices
					
			)
			,unnested_core_sample AS(
				SELECT indices.ordinality, indices.value AS is_core
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.is_core) as indices
					
			)
			--,segmented_points AS (
			SELECT 
				round(PC_Get(pt.point,'X'),3)::double precision AS X
					, round(PC_Get(pt.point,'Y'),3)::double precision AS Y
					, round(PC_Get(pt.point,'Z'),3)::double precision AS Z
					, round(PC_Get(pt.point,'reflectance'),3)::double precision AS Z
				,pt.ordinality AS index
				,round(i_patch_id,0)::int AS patch_id --have to use this trick to allow insert natively in plpgsql
				,ui.cluster_id 
				,ui2.is_core::int
			FROM  points as pt
				INNER JOIN unnested_cluster_id AS ui ON (pt.ordinality = ui.ordinality) 
				INNER JOIN unnested_core_sample AS ui2 ON (pt.ordinality = ui2.ordinality) 
			ORDER BY patch_id ASC,cluster_id ASC, index ASC; 
			RETURN; 
			END ; 
		$BODY$
	LANGUAGE plpgsql IMMUTABLE STRICT;
	--SELECT rc_patch_to_XYZ_array()

	 --test exemple
	SELECT result.*
	FROM riegl_pcpatch_space as rps
		,rc_patch_DBScan_clustering_points(rps.patch, rps.gid,_eps:=0.1::float,_min_samples:=50) AS result
	WHERE 
		gid = 1051; --1740	;
		--gid = 18875;
	*/
	/*
	COPY 
		( 

		WITH patch AS (
			SELECT min(gid) AS gid ,pc_union(patch) AS patch
			FROM riegl_pcpatch_space as rps
			WHERE ST_DWithin(patch::geometry, ST_MakePoint(1903,21224), 3)=TRUE
		)
		SELECT result.* -- , s_pid * result.cluster_id AS ccid
		FROM patch AS rps
			,rc_patch_DBScan_clustering_points(rps.patch, rps.gid,_eps:=0.15::float,_min_samples:=50) AS result
		WHERE ST_DWithin(patch::geometry, ST_MakePoint(1903,21224), 3)=TRUE
			--gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			--gid = 1740   --a patch with a cylinder?  
		)
	TO '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Patch_to_python/data/dbscan_clustering_small_area2.csv'-- '/tmp/temp_pointcloud.csv'
	WITH csv header;
	*/
