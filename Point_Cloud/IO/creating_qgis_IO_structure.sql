/***************************
*Rémi C
*
*we create the necessary data structure
***************************/

SET search_path to benchmark, public;


--first create a table to define the zone where we want to see points

	DROP TABLE IF EXISTS def_visu_qgis; 
	CREATE TABLE def_visu_qgis (
		gid SERIAL PRIMARY KEY
		,geom GEOMETRY(polygon, 932011)
	);
	CREATE INDEX ON def_visu_qgis USING GIST(geom)

--creating a tabele with all the point in the given def_visu_qgis are

	DROP TABLE IF EXISTS point_in_visu_qgis ;
	CREATE TABLE point_in_visu_qgis (
		gid SERIAL PRIMARY KEY
		,patch_id INT
		,geom GEOMETRY(POINTZ,932011),
		gps_time double precision,
		x double precision,
		y double precision,
		z double precision, 
		x_origin double precision,
		y_origin double precision, 
		z_origin double precision, 
		reflectance real,
		range real,
		theta real, 
		id int,
		class int, 
		num_echo int,
		nb_of_echo int
		,  FOREIGN KEY (patch_id) REFERENCES riegl_pcpatch_space (gid)
	);

	CREATE INDEX ON point_in_visu_qgis USING GIST(geom);
	CREATE INDEX ON point_in_visu_qgis (patch_id);
	CREATE INDEX ON point_in_visu_qgis (gps_time);
	CREATE INDEX ON point_in_visu_qgis (x);
	CREATE INDEX ON point_in_visu_qgis (y);
	CREATE INDEX ON point_in_visu_qgis (z);
	CREATE INDEX ON point_in_visu_qgis (x_origin);
	CREATE INDEX ON point_in_visu_qgis (y_origin);
	CREATE INDEX ON point_in_visu_qgis (z_origin);
	CREATE INDEX ON point_in_visu_qgis (reflectance);
	CREATE INDEX ON point_in_visu_qgis (range);
	CREATE INDEX ON point_in_visu_qgis (theta);
	CREATE INDEX ON point_in_visu_qgis (id);
	CREATE INDEX ON point_in_visu_qgis (class);
	CREATE INDEX ON point_in_visu_qgis (num_echo);
	CREATE INDEX ON point_in_visu_qgis (nb_of_echo);

--creating a function to synch the proxy point tbale content with ht epoint in the patch in the defined_zone

		DROP FUNCTION IF EXISTS rc_synch_point_in_visu_qgis();

		----
		--creating function
		CREATE OR REPLACE FUNCTION rc_synch_point_in_visu_qgis( )
		RETURNS  VOID AS $$ 
			--@brief this function synvh the content of point_in_visu_qgis with the conten of patch in def_visu_qgis
		 
		BEGIN 

			--find which patch should be converted to poitns

			WITH patch_to_be_synced AS (
				SELECT DISTINCT ON (rp.gid) rp.*
				FROM benchmark.riegl_pcpatch_space as rp
				INNER JOIN benchmark.def_visu_qgis as dvq ON (ST_Intersects(dvq.geom,ST_SetSRID(rp.patch::geometry,932011) ))
				ORDER BY rp.gid ASC --necessarey in case there are several overlapping polygon in def_visu_qgis
			)
			,deleting AS (
				DELETE FROM benchmark.point_in_visu_qgis AS pi
					WHERE NOT EXISTS (
						SELECT 1
						FROM patch_to_be_synced AS pt
						WHERE pi.patch_id= pt.gid
						)
					RETURNING pi.patch_id
			)
			--,inserting AS (
				INSERT INTO benchmark.point_in_visu_qgis  ( patch_id   ,geom ,gps_time,x ,y ,z ,x_origin ,y_origin ,z_origin ,reflectance ,range ,theta ,id ,class,num_echo,nb_of_echo)
					SELECT pt.patch_id
						, ST_SetSRID(pt::geometry,932011)
						,  PC_Get(pt, 'gps_time')
						,  PC_Get(pt, 'x')
						,  PC_Get(pt, 'y')
						,  PC_Get(pt, 'z')
						,  PC_Get(pt, 'x_origin')
						,  PC_Get(pt, 'y_origin')
						,  PC_Get(pt, 'z_origin')
						,  PC_Get(pt, 'reflectance')
						,  PC_Get(pt, 'range')
						,  PC_Get(pt, 'theta')
						,  PC_Get(pt, 'id')
						,  PC_Get(pt, 'class')
						,  PC_Get(pt, 'num_echo')
						,  PC_Get(pt, 'nb_of_echo')
					FROM (SELECT gid AS patch_id, PC_Explode(patch) AS pt FROM patch_to_be_synced ) AS pt
					WHERE NOT EXISTS (--we don't want to insert point that are already there. Note that this is not mutliprocess safe ! 
						SELECT 1 FROM benchmark.point_in_visu_qgis AS ptb WHERE pt.patch_id =ptb.gid  );
					   
		RETURN  ;
		END;
		$$ LANGUAGE 'plpgsql' VOLATILE;

		--test :  
		SELECT rc_synch_point_in_visu_qgis() ;


 --creating a trigger on the area to launch sync each time there is a change in it 

 
