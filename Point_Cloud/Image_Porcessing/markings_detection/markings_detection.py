# -*- coding: utf-8 -*-
"""
Created on Sun Sep 21 10:49:48 2014

@author: remi
"""

#imports
import numpy as np;
from osgeo import gdal ;

#data I/O
src_tif = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Data/rasterized_pointcloud_min_height/raster_1_all_attributes_min.tif'
dest_folder = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Image_Porcessing/markings_detection/' ; 


gtif = gdal.Open( src_tif ) ;

"""
Loading the reflectance band : number 7
    Band 1 =  Z 
    Band 2 = numbe rof points in this pixel (accumulated)
    Band 3 = GPS_Time
    Band 4 = x_origin
    Band 5 = y_origin
    Band 6 = Z_origin
    Band 7 = reflectance
    Band 8 = range
    Band 9 = theta
    Band 10 = id
    Band 11 = class
"""
refl  = np.array(gtif.GetRasterBand(7).ReadAsArray()) ;


"""
imshow(refl, cmap=plt.cm.gray) ; 
plt.show() ;
"""

#Now we convert the gradient of the reflectance image :
from skimage.morphology import disk,square
from skimage.filter.rank import gradient,threshold ;
from skimage.filter import sobel;
from skimage import img_as_float,img_as_uint,img_as_int; 
from skimage import viewer ;
from skimage.viewer.plugins import lineprofile ;