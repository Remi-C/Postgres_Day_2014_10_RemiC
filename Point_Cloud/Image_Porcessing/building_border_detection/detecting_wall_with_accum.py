# -*- coding: utf-8 -*-
"""
Created on Mon Aug 18 15:38:15 2014

@author: remi
"""

"""
python script to work on a Z image in order to extract sidewalk.
"""

#loading the required lib.


import Image
import numpy as np
from time import gmtime, strftime

#importing image :
src_tif = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Data/rasterized_pointcloud_min_height/raster_1_all_attributes_min.tif'
dest_folder = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Image_Porcessing/building_border_detection/' ; 

#we use gdal to read correctly the multiband tiff
from osgeo import gdal ;
gtif = gdal.Open( src_tif ) ;
 

"""
Now, we want to compute the relative height of point regarding the laser origin. So we perform : Z - Z_origin. In band term, it translates to 
    Band 1 =  Z 
    Band 6 = Z_origin
    Band 2 = numbe rof points in this pixel (accumulated)
"""

#getting all data into numpy array
Z = np.array(gtif.GetRasterBand(1).ReadAsArray()) ;
Z_origin  = np.array(gtif.GetRasterBand(6).ReadAsArray()) ;
Accum_points  = np.array(gtif.GetRasterBand(2).ReadAsArray()) ;

#showing input :
imshow(Z, cmap=plt.cm.gray) ;
imshow(Z_origin, cmap=plt.cm.gray) ;  
plt.show() ;

#computing the realtiv height
relativ_height = Z-Z_origin ;
imshow(relativ_height, cmap=plt.cm.gray) ;  plt.show() ;
#relativ_height[isnan(relativ_height)==False].size
#filtering
#keeping only relativ_height when more than 0 
filter_relativ_height = relativ_height ;
filter_relativ_height[filter_relativ_height<=0] = 0 ;
filter_relativ_height[filter_relativ_height>0] = 1 ;
##keeping only pixel where accum_points is bigger than 50
filter_accum_points = Accum_points ;
filter_accum_points[filter_accum_points<100]=0 ; 
filter_accum_points[filter_accum_points>=100].size ;

##result of filtering :
    
result_filtering = filter_accum_points * filter_relativ_height ;
#result_filtering[result_filtering <= 0].size

#result_filtering[(0 < result_filtering) & (result_filtering < 100)].size
#result_filtering[(100 < result_filtering) & (result_filtering < 2000)].size


#using some kind of straight skeleton on the result :
from skimage.morphology import skeletonize ;
from skimage.morphology import erosion, dilation, opening, closing, white_tophat , binary_closing;
from skimage.morphology import disk

import matplotlib.pyplot as plt
data_for_skeleton = result_filtering ;
data_for_skeleton[data_for_skeleton>0]=1 ;
imshow(data_for_skeleton, cmap=plt.cm.gray)
plt.show()

selem = disk(5) ;
closed = binary_closing(data_for_skeleton, selem) ;
imshow(closed, cmap=plt.cm.gray) ; plt.show() ;
closed[closed>0]=1 ;
skeleton = skeletonize(data_for_skeleton)
imshow(skeleton, cmap=plt.cm.gray) ; plt.show() ;



#trying to extract lines with hough transform
from skimage.transform import (hough_line, hough_line_peaks,
                               probabilistic_hough_line)
lines = probabilistic_hough_line(skeleton, threshold=10, line_length=5, line_gap=20)
for line in lines:
    p0, p1 = line ;
    plt.plot((p0[0], p1[0]), (p0[1], p1[1])) ;

imshow(skeleton, cmap=plt.cm.gray) ; plt.show() ;
#working on sidewalk :
    """
        We work on sidewalk : we use the relative height to compute the gradient 
        of it. Then we perform thresholding then closing then straight sekeleton
        NOte : the laser is approximately 2.50 meters above the street.
        We are only interested in pixel where the height is between +-50cm from the ground
            , to keep sidewalk.
    """

from skimage.morphology import disk,square
from skimage.filter.rank import gradient,threshold ;
from skimage import img_as_float,img_as_uint,img_as_int; 
from skimage import viewer ;
from skimage.viewer.plugins import lineprofile ;

#filtering the relative height again : we keep only pixel with relativ height between -3 and -2 meters, that is around the height of sidewalk + some margin

filter_relativ_height_sidewalk = relativ_height ;
filter_relativ_height_sidewalk[(filter_relativ_height_sidewalk<-3)|(filter_relativ_height_sidewalk>-2)| isnan(filter_relativ_height_sidewalk)==True  ] = 0; 
filter_relativ_height_sidewalk[ filter_relativ_height_sidewalk!=0] = 1
#filter_relativ_height_sidewalk = (filter_relativ_height_sidewalk +2.5)*2 ;

 
filter_relativ_height_sidewalk[(isnan(filter_relativ_height_sidewalk)==False)]
imshow(filter_relativ_height_sidewalk, cmap=plt.cm.gray) ; plt.show();

Z_around_sidewalk = Z * filter_relativ_height_sidewalk ; 
imshow(Z_around_sidewalk, cmap=plt.cm.gray) ;
#Z_around_sidewalk[Z_around_sidewalk!=0]
new_viewer = viewer.ImageViewer(Z_around_sidewalk) ; new_viewer.show() ; 


convert_to_float = img_as_float(filter_relativ_height_sidewalk) 
convert_to_float[isnan(convert_to_float)==False]

convert_to_int = img_as_int(filter_relativ_height_sidewalk) ; 
grad =  gradient(convert_to_int,disk(1)) ;



new_viewer = viewer.ImageViewer(grad)
new_viewer += lineprofile.LineProfile()
new_viewer.show()

imshow(grad, cmap=plt.cm.gray); plt.show();


 
from skimage.morphology import disk
from skimage.filter.rank import gradient
  

#outputting the raster to see if it worked :
    
geotransform = gtif.GetGeoTransform()

rasterOrigin = (geotransform[0],geotransform[3])
pixelWidth = geotransform[1] ; 
pixelHeight = geotransform[5] ; 
newRasterfn = dest_folder+'result_straight_skeleton'+strftime("%Y-%m-%d_%H_%M_%S", gmtime()) +'.tif'
array = skeleton
array2raster(newRasterfn,rasterOrigin,pixelWidth,pixelHeight,array) ;# convert array to raster

#help(gdal.ReprojectImage)


def array2raster(newRasterfn,rasterOrigin,pixelWidth,pixelHeight,array) :
    #array =  array[::-1] #to invert array : not sure it is usefull
    cols = array.shape[1]
    rows = array.shape[0]
    originX = rasterOrigin[0]
    originY = rasterOrigin[1]
    driver = gdal.GetDriverByName('GTiff')
    outRaster = driver.Create(newRasterfn, cols, rows, 1, gdal.GDT_Float32)
    outRaster.SetGeoTransform((originX, pixelWidth, 0, originY, 0, pixelHeight))
    outband = outRaster.GetRasterBand(1)
    outband.WriteArray(array)
    #outRasterSRS = osr.SpatialReference()
    #outRasterSRS.ImportFromEPSG(4326)
    #outRaster.SetProjection(outRasterSRS.ExportToWkt())
    outband.FlushCache();

