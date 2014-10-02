Postgres_Day_2014_10_RemiC
==========================

usefull instruction and file about the postgres day presentation of pointlcoud use with postgres

 
The [talk](http://www.postgresql-sessions.org/6/start) in September presents how to use this :
 * Introduction to a new GIS data : Point Cloud
 * Why is it better to store this data in DBMS?
 * Fast loading/query 
  * load billions of points
  * fast retrieval
  * fast filtering
 * In base processing 
  * convert points to image (raster)
  * in base image processing for detection in pointcloud (sidewalk, buildings, markings)
  * in base point cloud processing for 
   * plane detection (using pcl)
   * structural vector detection (using scilearn and ICA) 
   * automatic clustering (pcl+scilearn).
 * Complex architecture
  * interactive exploration of massiv point cloud in browser. 
  * Interactive pointcloud algorithm control in browser.
