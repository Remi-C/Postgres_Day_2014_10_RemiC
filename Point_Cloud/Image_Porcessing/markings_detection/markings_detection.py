# -*- coding: utf-8 -*-
"""
Created on Sun Sep 21 10:49:48 2014

@author: remi
"""

#imports
import numpy as np;
from osgeo import gdal ;
from scipy.fftpack import fft2;
from skimage.morphology import disk,square
from skimage.filter.rank import gradient,threshold ;
from skimage.filter import sobel;
from skimage import img_as_float,img_as_uint,img_as_int; 
from skimage import viewer ;
from skimage.viewer.plugins import lineprofile ; 
from skimage.restoration import denoise_bilateral

from skimage.morphology import skeletonize ;
from skimage.morphology import erosion, dilation, opening, closing, white_tophat , binary_closing;
from skimage.morphology import disk
from skimage.transform import hough_line, hough_line_peaks,  probabilistic_hough_line
from sklearn.preprocessing import normalize  ;

from skimage.filter import gaussian_filter

#data I/O
src_tif = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Data/rasterized_pointcloud_min_height/raster_1_all_attributes_min.tif'
dest_folder = '/media/sf_E_RemiCura/PROJETS/Postgres_Day_2014_10_RemiC/Point_Cloud/Image_Porcessing/markings_detection/' ; 
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


####loading data###

gtif = gdal.Open( src_tif ) ;
refl  = np.array(gtif.GetRasterBand(7).ReadAsArray()) ;

"""
imshow(refl, cmap=plt.cm.gray) ; 
plt.show() ;
"""

#Now we convert the gradient of the reflectance image : 

#noramlizing on image
tmp_min = np.min(refl[isnan(refl)==False]) ;
tmp_max = np.max(refl[isnan(refl)==False]) ;
refl_n= (refl -  tmp_min ) / (tmp_max-tmp_min)  ;
"""normalized between 0 and 1"""
  
  
####creating a mask for Nan and strong gradient on Z (we want flat places)###
  
#creating a mask around nan values to be able to remove it from computing
nan_mask = refl ;
nan_mask[isnan(nan_mask)==True] = 0 ; 
nan_mask = nan_mask.astype(np.bool)
nan_mask = erosion(nan_mask, disk(3))

#filtering with element with strong height gradient : we are looking for flat markings.
Z = np.array(gtif.GetRasterBand(1).ReadAsArray()) ;
tmp_min = np.min(Z[isnan(Z)==False]) ;
tmp_max = np.max(Z[isnan(Z)==False]) ;
Z_n= (Z -(tmp_max+tmp_min)/2.0 ) / (tmp_max-tmp_min)  ;
soble_Z = sobel(Z_n ) ; 
#imshow(soble_Z, cmap=plt.cm.gray,interpolation="none") ;  
#viewer.ImageViewer(soble_Z).show() ; 
height_nan_mask = soble_Z
height_nan_mask[height_nan_mask>0.01] = 0 ; 
height_nan_mask[height_nan_mask!=0] = 1 ; 
height_nan_mask = height_nan_mask.astype(np.bool)
height_nan_mask = erosion(height_nan_mask, disk(5))
#viewer.ImageViewer(height_nan_mask).show() ; 
  

###smoothing of image, using a bilateral filter###

refl_n_f = img_as_float(refl_n,True) ;  
refl_n_f[isnan(refl_n_f)==True] = 0 ; """We have to cast nan to 0, the denoising doesn't understand Nan"""
#imshow(refl_n_f, cmap=plt.cm.gray) ; 
#plt.show() ;
den = denoise_bilateral(refl_n_f, sigma_range=0.085, sigma_spatial=3) ;

np.histogram(den)
den[isnan(den)==True]
#imshow(den, cmap=plt.cm.gray,interpolation="none") ; 
#plt.show() ;
#viewer.ImageViewer(den) ;
  
  
###gradient of smoothed image###  
sobel_result = sobel(den,height_nan_mask) ; 
#imshow(sobel_result, cmap=plt.cm.gray,interpolation="none") ; 
#viewer.ImageViewer(sobel_result).show() ; 

#threshold :
sobel_thres = sobel_result ;
sobel_thres[sobel_thres<0.05] = 0 ;
imshow( sobel_thres, cmap=plt.cm.gray,interpolation="none") ; 



####line detection###

lines = probabilistic_hough_line(sobel_thres, threshold=10, line_length=6, line_gap=3)
len(lines)

for line in lines:
    p0, p1 = line ;
    plt.plot((p0[0], p1[0]), (p0[1], p1[1])) ;

imshow(sobel_thres, cmap=plt.cm.gray) ; plt.show() ;


###line clustering###
"""We need to merge the lines to find the finale ones.
Fro this we want to compute angle of the lines (compared ot origin axisfor instance)
, then cluster on middle points coordinate + angle 
We need to perform some operation on angle so that some known angles comes together ()
(for instance, parallel and orthogonale lines, 30 degrées lines, 60 degrées lines ...)
"""


from numpy.fft import fftshift
fft = fftshift(fft2((sobel_thres - np.mean(sobel_thres))))
pow = log(real(multiply(fft, fft.conjugate())))
imshow(pow , cmap=plt.cm.gray) ; plt.show() ;


viewer.ImageViewer(pow/10.0 ).show() ;

fft_of_fft =  normalize(pow, norm='l2', axis=1, copy=True);
fft_of_fft_2 = gaussian_filter(fft_of_fft, 5)
imshow(fft_of_fft_2, cmap=plt.cm.gray) ; plt.show() ;

lines_fft = probabilistic_hough_line(fft_of_fft_2, threshold=10, line_length=100, line_gap=30) ;
len(lines_fft) ;

lines_fft

fft_of_fft[fft_of_fft<0.5]=0; 
imshow(fft_of_fft, cmap=plt.cm.gray) ; plt.show() ;

 sklearn.preprocessing.normalize(pow, norm='l2', axis=1, copy=True)¶

fft_2 = fftshift(fft2(  fft_of_fft  ))
pow_2 = log(real(multiply(fft_2, fft_2.conjugate()))) 
imshow(pow_2, cmap=plt.cm.gray) ; plt.show() ;
  
image_fft = fft2(refl)

imshow(image_fft, cmap=plt.cm.gray) ; plt.show() ;




