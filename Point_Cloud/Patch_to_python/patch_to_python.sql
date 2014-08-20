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
	SELECT gid, PC_NumPoints(patch) AS npoints
	FROM riegl_pcpatch_space as rps
	WHERE ST_DWithin(rps.patch::geometry, ST_MakePoint(1899.56,21226.90),0.1)=TRUE
	ORDER BY npoints ASC ;

	--we work on patch 8480 for example, with 2269 points 

--creating a function to convert patch points into array of [X Y Z ]

	--we need an array agg for array, found in PPPP_utilities

			CREATE AGGREGATE array_agg_custom(anyarray)
				(
				SFUNC = array_cat,
				STYPE = anyarray
				);

	--a wrapper function to convert from patch to array[array[]], so to be able to transmit information	
	DROP FUNCTION IF EXISTS rc_patch_to_XYZ_array(ipatch PCPATCH);
	CREATE OR REPLACE FUNCTION rc_patch_to_XYZ_array(ipatch PCPATCH
		)
	  RETURNS FLOAT[][]AS
	$BODY$
			--@brief this function clean result tables
			-- @return :  nothing 
			DECLARE 
			BEGIN
				
				RETURN array_agg_custom(ARRAY[ARRAY[ PC_Get(point,'X')::float , PC_Get(point,'Z')::float , PC_Get(point,'Y')::float] ])
				FROM PC_Explode(ipatch) as point ;
				--RETURN NULL;
			END ;
		$BODY$
	LANGUAGE plpgsql VOLATILE;
	--SELECT rc_patch_to_XYZ_array()

	SELECT gid, PC_NumPoints(patch) AS npoints , rc_patch_to_XYZ_array(patch) as result
	FROM riegl_pcpatch_space as rps
	WHERE --gid = 8480 
		gid = 18875;


	--a plpython function taking the array of double precision and printing what it understands of it
CREATE FUNCTION rc_py_point_array_to_numpy_array (iar FLOAT[][])
  RETURNS VOID
AS $$
 plpy.notice(iar) ; 
 return null; 
$$ LANGUAGE plpythonu;
	
	
	SELECT gid, PC_NumPoints(patch) AS npoints , rc_py_point_array_to_numpy_array(result)
	FROM riegl_pcpatch_space as rps,rc_patch_to_XYZ_array(patch) as result
	WHERE --gid = 8480 
		gid = 18875;
	
