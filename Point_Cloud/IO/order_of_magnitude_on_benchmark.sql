set search_path to benchmark, public;

select count(*)
FROM riegl_pcpatch_space  
--23996

SELECT sum(PC_NumPoints(patch))
FROM riegl_pcpatch_space  
--12000000

--pgadmin : 
--table-size : 		10 Mo
--toast table size : 	293 Mo
-- index size : 		5.5 Mo

--having 4 indexes :  
	-- index on PC_Numpoints()
	-- index on patch::geometry
	-- index on ST_SetSRID(patch::geometry) 
	-- index on   rc_compute_range_for_a_patch(patch, 'gps_time') ;