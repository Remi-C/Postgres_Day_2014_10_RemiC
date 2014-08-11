/*
*Rémi Cura, 2014
* 
* 
*
*This PL/R function will compute a clustering  
*Use nnclust, a r clustering package 
*/

CREATE SCHEMA IF NOT EXISTS plr_clustering;
 SET search_path to plr_clustering,public;

 --ALTER TABLE temp_toto_demo RENAME TO clustering_data
 
SELECT *
FROM clustering_data;

----importing the data

DROP TABLE IF EXISTS full_clustering_set;
CREATE TABLE full_clustering_set
(
  gid bigint,
  x numeric,
  y numeric,
  z numeric,
  reflectance numeric,
  patch_gid integer,
  num_points integer,
  has_lod integer,
  ordinality bigint,
  lod0 integer, lod1 integer, lod2 integer, lod3 integer,lod4 integer,lod5 integer,lod6 integer,  lod7 integer, lod8 integer, lod9 integer
);

COPY reduced_clustering_set FROM '/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/reduced_clustering_cloud.csv' WITH CSV HEADER;



DROP TABLE IF EXISTS reduced_clustering_set;
CREATE TABLE reduced_clustering_set
(
  gid bigint,
  x numeric,
  y numeric,
  z numeric,
  reflectance numeric,
  patch_gid integer,
  num_points integer,
  has_lod integer,
  ordinality bigint,
  lod0 integer,  lod1 integer, lod2 integer,lod3 integer, lod4 integer, lod5 integer, lod6 integer, lod7 integer,  lod8 integer,lod9 integer
);

COPY full_clustering_set FROM '/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/full_clustering_cloud.csv' WITH CSV HEADER;



/*
--note : this querry act as a kernel over data to change the kind of distance that will be used in the clustering. 
--We normalize reflectance because as the patch is 1 m2 , x,y,z have already been normalized (but not centered, yet it doesn't matter).
	WITH minmax AS (
		SELECT max(reflectance) as max, min(reflectance) as min
		FROM clustering_data 
	)
	UPDATE clustering_data SET reflectance = reflectance/(abs(max-min))
	FROM minmax
*/

/*
	CREATE TABLE IF NOT EXISTS  plr_modules (
		modseq int4,
		modsrc text
		);

	INSERT INTO plr_modules
	VALUES (0, 'library(nnclustl)' );

	--SELECT * FROM reload_plr_modules();
*/
 
DROP FUNCTION IF EXISTS  rc_plr_cluster_using_nnclust (query_to_get_data text, the_threshold numeric, the_fill numeric, the_giveup numeric, the_maxclust NUMERIC );
CREATE OR REPLACE FUNCTION  rc_plr_cluster_using_nnclust (query_to_get_data text, the_threshold numeric, the_fill numeric, the_giveup numeric, the_maxclust NUMERIC ) 
RETURNS setof record AS 
$$
	#settings :
		##ensuring that integer will still be noted as integer (no scientific notation)
		options("scipen"=100, "digits"=16)
	##printing inputs
	msg <- paste("inputs SQL query :  ", query_to_get_data);
	pg.thrownotice(msg);

	##preparing select statement to get the values to cluster
	the_query <- query_to_get_data ;

	##executing select statement to get data
	data_to_cluster <-  pg.spi.factor(pg.spi.exec(the_query));

	##some warning if the first column is not full of int :
	#note : we can't just check type because of limited size of int : a big int could be mapped to numeric
	test_sample <- data_to_cluster[sample(1:(1+round(nrow(data_to_cluster)/100)), 1),1] ; #we take random sample in first column (1/100 of col size)
	if( test_sample!= round(test_sample) ) pg.throwerror(paste("WARNING : first column of data to cluster MUST BE an int identigfier (gid)"));#if samples are not integer, throw error

	##special cas : when only 1 sample : nncluster bugs 
	if(nrow(data_to_cluster)<=1) return(data.frame(data_to_cluster[1],0));
	
	##beginninng of data clustering 
	#loading the right library
	pg.thrownotice( "loading the right library");
	loading_lib <- library(nnclust,logical.return = TRUE) ; 
	pg.thrownotice( paste("the library successfully loaded : ", loading_lib));
	
	#computing clustering
	pg.thrownotice("computing clustering");
	clustering <- nncluster( #function to compute clustering, result are hold in clustering which is a dataframe
		data.matrix(data_to_cluster[2:(ncol(data_to_cluster)*1)]), ##data on which do the clustering : all input data except gid column (first one), all put in a matrix form
		threshold = the_threshold , 
		fill = the_fill, 
		give.up = the_giveup, 
		verbose=TRUE ,
		maxclust = the_maxclust, 
		start=NULL);

	#creating a plot output 
	#timestamp <- toString(pg.spi.factor(pg.spi.exec("SELECT CURRENT_TIMESTAMP(1) AS timestamp"))[1,1] );

	now <- format(Sys.time(), "%Y_%m_%d %H-%M-%S-%OS2");
	#extracting the info to put it in files
	the_info <- unlist(regmatches(query_to_get_data,regexec("'([^_]*_[^']*)'",query_to_get_data)))[2];
	
	#pg.thrownotice(paste(" now2 : ",now," the_info : ",the_info));
	output_directory<-paste("/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/clusters_plot-",now,"__",the_info,".png",sep="");
	pg.thrownotice(paste("creating a plot output in ",output_directory));
	png(
		filename = output_directory,
		width = 1920,
		height = 1400,
		units= "px");
	par("oma"=c(1,1,10,1));

	x<-0;
	if (is.na(clusterMember(clustering, outlier = FALSE))==TRUE) 
			{x<- x+1;
			the_label <- x;} 
		else {
			the_label <- clusterMember(clustering, outlier = FALSE)};

	#pg.thrownotice(toString(the_label));
	
	plot( data_to_cluster[3:4], col=the_label , pch=20, main = paste(now,query_to_get_data,sep="	"));
	dev.off();

	
	#create the return type : a data.frame with a column gid and a column cluster_label
	pg.thrownotice("creating return result");
	return(data.frame(data_to_cluster[1],clusterMember(clustering, outlier = FALSE)));
	
	#return(TRUE);
	#return data_to_cluster;
$$ LANGUAGE 'plr' STRICT;
  
--querry to cluster : detecting the ground 
DROP TABLE IF EXISTS result_clustering;
CREATE TABLE result_clustering AS --191  point, 0.5 sec
WITH result_clustering AS ( 
	SELECT *
	FROM rc_plr_cluster_using_nnclust (
			'WITH minmax AS(
				SELECT min(reflectance) as min, max(reflectance) AS max
				FROM reduced_clustering_set
			)
			SELECT gid, x,y,100*z,round(1) AS reflectance
			FROM minmax, reduced_clustering_set
			ORDER BY gid ASC
			'
			-- ,10*reflectance/ (abs(max-min)) 
			-- x^2+y^2
			-- LIMIT 10000 
			::text
			, the_threshold:= 0.1
			, the_fill:=1
			, the_giveup:=500
			, the_maxclust:=50) AS f(gid bigint, cluster_id bigint)
	)
	SELECT cd.*, rc.cluster_id
	FROM result_clustering as rc LEFT OUTER JOIN  reduced_clustering_set as cd ON cd.gid = rc.gid;
	
--outputting the data to visualize it
SELECT cluster_id ,  count(*)  AS pt_in_cluster
FROM  result_clustering
GROUP BY cluster_id ;

select *
FROM 
(
WITH minmax AS(
	SELECT min(reflectance) as min, max(reflectance) AS max
	FROM reduced_clustering_set
)
SELECT gid, x,y,z,2*reflectance/ (abs(max-min)) AS reflectance
FROM minmax, reduced_clustering_set
ORDER BY x^2+y^2
LIMIT 10000 ) as sub
ORDER BY reflectance ASC;


			
COPY (
	SELECT gid, x, y, z, reflectance, COALESCE(cluster_id,0) as cluster_id
	FROM result_clustering 
	) TO '/media/sf_E_RemiCura/PROJETS/postgres_day_09_2014/PLR_demo/clustering/result_clustering.csv' WITH CSV HEADER
	