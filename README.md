Postgres_Day_2014_10_RemiC
==========================

usefull instruction and file about the postgres day presentation of pointlcoud use with postgres


In postgres data server (SGBD), you can create function written in python (using CREATE LANGAGE PLPYTHONU).
This kind of server can be hacked into a Point Cloud server using PostGis and an extension called [pointcloud]( https://github.com/pramsey/pointcloud ).
The work is [here](https://github.com/Remi-C/Postgres_Day_2014_10_RemiC) and [here](https://github.com/Remi-C/Pointcloud_in_db)

The [talk](http://www.postgresql-sessions.org/6/start) in September presents how to use this :
* basics
  * load billions of points
  * fast retrieval
  * fast filtering
* processing
  * convert points to image (raster)
    * in base image processing for detection in pointcloud (sidewalk, buildings)
  * in base point cloud processing for 
    * plane detection (using pcl)
    * structural vector detection (using scilearn and ICA) 
    * automatic clustering (pcl+scilearn).
* visualization
 * interactive exploration of massiv point cloud in browser. 
 * Interactive pointcloud algorithm control in browser.

I like this python-pcl, I hope more cool stuff will be added to it !
Cheers,
Rémi-C
For the clustering I use the DBScan algorithm, and it would give better result with normals 
