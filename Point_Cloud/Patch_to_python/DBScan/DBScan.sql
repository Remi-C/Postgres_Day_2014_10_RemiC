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
DROP FUNCTION IF EXISTS rc_py_dbscan ( DOUBLE PRECISION[],data_dim INT, _eps float, _min_samples float, with_verticality BOOLEAN, with_outliers_removal BOOLEAN);
CREATE FUNCTION rc_py_dbscan (
	iar  DOUBLE PRECISION[] 
	,data_dim INT DEFAULT 3
	, _eps float DEFAULT 0.01
	, _min_samples float DEFAULT 10
	,with_verticality BOOLEAN DEFAULT TRUE
	,with_outliers_removal BOOLEAN DEFAULT TRUE
	,OUT cluster_id INT[]
	,OUT is_core BOOLEAN[]
	,OUT verticality FLOAT[]
	,OUT indices INT[]
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
import numpy.lib.recfunctions as recfunctions ;


#converting from 1D list to 2D numpy array (array of 4D points)
np_array = np.reshape(np.array(iar), (-1, data_dim)); 
np_array-=np.nanmax(np_array, axis=0) ; 
#safeguard : replace all values NaN or infinity by a vey low value
np_array = np.nan_to_num(np_array).astype(np.float32) ; 
indices = np.arange(len(np_array)).astype(np.float32);
verticality = np.asarray([-1] * len(np_array)) ;

if with_outliers_removal == True: 
	#filtering in the X,Y,Reflectance space , to remove too strong outliers
	p_xyrefl = pcl.PointCloud() ;
	p_xyrefl.from_array(np_array[:,:][:,[0,1,3]] ) ;


	fil = p_xyrefl.make_statistical_outlier_filter()
	fil.set_mean_k(30)
	fil.set_std_dev_mul_thresh(1.5)
	filtered_reflectance = fil.filter().to_array(); 
		#plpy.notice(filtered_reflectance);
	 
	filtered_reflectance.dtype =[('X', np.float32), ('Y', np.float32), ('reflectance_b',np.float32 ) ]; 
	local_arr  = np.concatenate((np_array, indices[:,np.newaxis]), axis=1);  
	local_arr.dtype = [('X', np.float32), ('Y', np.float32), ('Z', np.float32), ('reflectance',np.float32 ),  ('indices',np.float32 ) ]; 
	#now we need to get back the Z value. For this we have to perform a join to the original array, so we get back the Z. 
	#it is quite ugly to do this using pure numpy...
	cols = list(set(np_array.dtype.names).intersection(filtered_reflectance.dtype.names)) ; 
	result = recfunctions.join_by(cols, local_arr, filtered_reflectance, jointype='inner')  ;
	indices = result['indices'] ; #now contains the indice of all points that have been keept

	dtype_XYZRef = [('X', np.float32), ('Y', np.float32), ('Z', np.float32), ('reflectance',np.float32 ) ]; 

	np_array = result[['X','Y','Z','reflectance']].view((np.float32, len(dtype_XYZRef)) ) ;
	#plpy.notice(filtered_np_array); 
	


if with_verticality == True:  
	#creating a point cloud to compute normals
	#reshaping the numpy array to keep only X, Y , Z
	geom_array  = np_array[:,0:3 ].astype(np.float32) ;
	#plpy.notice(geom_array) ;
	#creating a point cloud with this array of points
	_p = pcl.PointCloud() ;
	_p.from_array( geom_array) ;
	#computing the normal of the point clouds, keeping only the Z component :  
		#We applya sqrt on it because sqrt[0,1]->[0,1] and boost dynamic for values belove 0.5 and diminish dynamic for value above 0.5. 
		#This is another way to say : is something is mostly vertical, it is vertical, is something is almost not vertical, nuances are important.
		#We apply a small correcting values to limit influence of verticaliity a bit.
		#of course we should apply a smoothing filter for proper results
	verticality = np.sqrt((abs(1-abs(_p.calc_normals(-1,0.05)[:,2]))))  /3.0; 
		#plpy.notice(normals) ;  

		#plpy.notice(geom_array.shape);
		#plpy.notice((normals).shape);
	#adding the verticality score to input array :
	np_array = np.concatenate((geom_array, verticality[:,np.newaxis]), axis=1); 
	#plpy.notice(geom_array); 



#performing clustering 
np_array = np.nan_to_num(np_array).astype(np.float32) ; 
for i in np_array:
	plpy.notice( i ) ; 
db = DBSCAN(eps= _eps, min_samples = _min_samples,algorithm='auto',leaf_size=30, p=2 ).fit(np_array) ;
core_samples_mask = np.zeros_like(db.labels_, dtype=bool) ;
core_samples_mask[db.core_sample_indices_] = True ;
labels = db.labels_ ;
#plpy.notice(labels.dtype) ;
#plpy.notice(core_samples_mask) ;
#plpy.notice(labels.size) ;

return ((labels.astype(np.int32)) 
		, (core_samples_mask.astype(np.bool)) 
		, (verticality.astype(np.float32)) 
		,  (indices.astype(np.int32)) ); #converting from double to int32

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
-- 					,_eps := 0.1
-- 					,_min_samples := 50
-- 					,with_verticality:= TRUE) AS result
-- 		)
-- 		,unnested_indices AS(
-- 			SELECT unnest(result)
-- 			FROM segmented_indices
-- 		)
-- 		SELECT DISTINCT *
-- 		FROM unnested_indices;



		--a utility function that will take a patch and ouput rows of pointcloud data suitable for exporting :
	DROP FUNCTION IF EXISTS rc_patch_DBScan_clustering_points(ipatch PCPATCH, patch_id INT, FLOAT,INT , boolean, boolean);
	CREATE OR REPLACE FUNCTION rc_patch_DBScan_clustering_points(ipatch PCPATCH, i_patch_id INT,_eps FLOAT DEFAULT 0.1, _min_samples INT  DEFAULT 10
		,_with_verticality BOOLEAN DEFAULT TRUE
		,_with_outliers_removal BOOLEAN DEFAULT TRUE)
	  RETURNS TABLE (X DOUBLE PRECISION,Y DOUBLE PRECISION , Z DOUBLE PRECISION, reflectance DOUBLE PRECISION
		, index INT
		,filtered INT
		, patch_id INT
		, verticality FLOAT
		, cluster_id int, is_core INT)
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
							,1 -- PC_Get(pt.point,'reflectance')::float/40.0
						] ORDER BY pt.ordinality ASC ) as arr
				FROM points as pt
			)
			,segmented_indices AS (---get the indexes of points resulting from segmentation
				SELECT result.*  
				FROM points_coordinate_ad_float_arr as float_arr
					,   rc_py_dbscan ( iar := float_arr.arr  
						,data_dim :=4
						,_eps := _eps
						,_min_samples := _min_samples
						,with_verticality:= _with_verticality 
						,with_outliers_removal := _with_outliers_removal) AS result
			)
			,unnested_indices AS(
				SELECT indices.ordinality, indices.value AS indices
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.indices) as indices
					
			)
			,unnested_cluster_id AS(
				SELECT indices.ordinality, indices.value AS cluster_id
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.cluster_id) as indices
					
			)
			,unnested_core_sample AS(
				SELECT indices.ordinality, indices.value AS is_core
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.is_core) as indices
					
			)
			,unnested_verticality AS(
				SELECT indices.ordinality, indices.value AS verticality
				FROM segmented_indices AS si,rc_unnest_with_ordinality( si.verticality) as indices
					
			)
			--,segmented_points AS (
			SELECT 
				round(PC_Get(pt.point,'X'),3)::double precision AS X
					, round(PC_Get(pt.point,'Y'),3)::double precision AS Y
					, round(PC_Get(pt.point,'Z'),3)::double precision AS Z
					, round(PC_Get(pt.point,'reflectance'),3)::double precision AS Z
				,pt.ordinality AS index
				,COALESCE((pt.ordinality != ui.indices)::int,1) AS filtered
				,round(i_patch_id,0)::int AS patch_id --have to use this trick to allow insert natively in plpgsql
				,COALESCE(ui3.verticality, -1) As verticality
				,COALESCE(ui1.cluster_id , -2) AS cluster_id 
				,COALESCE(ui2.is_core::int, -1 ) AS is_core
			FROM  points as pt
				LEFT OUTER JOIN unnested_indices as ui ON (pt.ordinality  = ui.indices)
				LEFT OUTER JOIN unnested_cluster_id AS ui1 ON (ui.indices = ui1.ordinality) 
				LEFT OUTER JOIN unnested_core_sample AS ui2 ON (ui.indices = ui2.ordinality) 
				LEFT OUTER JOIN unnested_verticality AS ui3 ON (ui.indices = ui3.ordinality) 
			ORDER BY patch_id ASC,cluster_id ASC, index ASC; 
			RETURN; 
			END ; 
		$BODY$
	LANGUAGE plpgsql IMMUTABLE STRICT;
	--SELECT rc_patch_to_XYZ_array()
/*
	 --test exemple
	SELECT result.*
	FROM riegl_pcpatch_space as rps
		,rc_patch_DBScan_clustering_points(rps.patch, rps.gid,_eps:=0.1::float,_min_samples:=50) AS result
	WHERE 
		--gid = 1051; --1740	;
		gid = 18875;
*/



	COPY 
		( 

		WITH patch AS (
			--SELECT min(gid) AS gid ,pc_union(patch) AS patch
			SELECT gid ,patch AS patch
			FROM riegl_pcpatch_space as rps
			WHERE -- ST_DWithin(patch::geometry, ST_MakePoint(1903,21224), 1)=TRUE
				gid = 1740
				--gid = 1051
		)
		SELECT  --result.* -- , s_pid * result.cluster_id AS ccid
			X ,Y ,Z ,reflectance  
			,index  
			,filtered
			,verticality 
			,patch_id  
			,cluster_id
			,is_core
		FROM patch AS rps
			,rc_patch_DBScan_clustering_points(rps.patch, rps.gid
					,_eps:=0.1::float
					,_min_samples:=80
					,_with_outliers_removal := FALSE
					,_with_verticality :=  FALSE) AS result
		--WHERE ST_DWithin(patch::geometry, ST_MakePoint(1903,21224), 3)=TRUE
			--gid = 8480 
			--gid = 18875 -- very small patch
			--gid = 1598 
			--gid = 1051 -- a patch half hozirontal, half vertical . COntain several plans
			--gid = 1740   --a patch with a cylinder?  
		)
	TO '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Patch_to_python/data/dbscan_clustering_with_verticality_small_area.csv'-- '/tmp/temp_pointcloud.csv'
	WITH csv header;
 
