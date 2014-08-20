# -*- coding: utf-8 -*-
"""
Created on Wed Aug 20 19:52:18 2014

@author: remi

This module group stuff to  be able to deal with converting from pointcloud 
to PCL and to perform some basic stuff
"""


def list_of_point_to_pcl(iar):
    """coinvert list of 3D points to a pcl cloud 

    :param iar:  -- a list of pcoints coordinate following the pattern X,Y,Z,X,Y,Z ... 
    :return: a pointcloud object containing all the points
    """
    import numpy as np ;
    import pcl ;
    #converting the 1D array to 2D array
    #np_array = np.reshape(np.array(iar), (-1, 3)).astype(np.float32)  ; # note : we duplicate the data (copy), because we have to assume input data is read only
    
    #importing this numpy array as pointcloud
    p = pcl.PointCloud() ;
    p.from_array( 
        np.reshape(np.array(iar), (-1, 3)).astype(np.float32)
        ) ;
    return p;
    
def perform_1_ransac_segmentation(
    p
    , _ksearch
    , sac_model
    , _distance_weight
    , _max_iterations
    , _distance_threshold):
    """given a pointcloud, perform ransac segmetnation on it 
    :param p:  the point cloud
    :param _ksearch: number of neighboor considered for normal computation
    :param sac_model: the type of feature we are looking for. Can be pcl.SACMODEL_NORMAL_PLANE
    :param _distance_weight: between 0 and 1 . 0 make the filtering selective, 1 not selective
    :param _max_iterations: how many ransac iterations?
    :param _distance_threshold: how far can be a point from the feature to be considered in it?
    :return indices: the indices of the point in p that belongs to the feature
    :return model: the model of the feature
    """
    import numpy as np ;
    import pcl ;
    #prepare segmentation
    seg = p.make_segmenter_normals(ksearch=_ksearch)
    seg.set_optimize_coefficients (True);
    seg.set_model_type (pcl.SACMODEL_NORMAL_PLANE)
    seg.set_normal_distance_weight (_distance_weight) #Note : playing with this make the result more (0.5) or less(0.1) selective
    seg.set_method_type (pcl.SAC_RANSAC)
    seg.set_max_iterations (_max_iterations)
    seg.set_distance_threshold (_distance_threshold)
    #segment
    indices, model = seg.segment()  ; 
    
    return indices, model;
    
    
def perform_N_ransac_segmentation(
    p
    ,min_support_points
    ,max_plane_number
    , _ksearch
    , sac_model
    , _distance_weight
    , _max_iterations
    , _distance_threshold):
    """given a pointcloud, perform ransac segmetnation on it 
    :param p:  the point cloud
    :param min_support_points: minimal number of points that should compose the feature 
    :param max_plane_number: maximum number of feature we want to find
    :param _ksearch: number of neighboor considered for normal computation
    :param sac_model: the type of feature we are looking for. Can be pcl.SACMODEL_NORMAL_PLANE
    :param _distance_weight: between 0 and 1 . 0 make the filtering selective, 1 not selective
    :param _max_iterations: how many ransac iterations?
    :param _distance_threshold: how far can be a point from the feature to be considered in it?
    :return indices: the indices of the point in p that belongs to the feature
    :return model: the model of the feature
    """
    import numpy as np ;
    import pcl ;
    import plpy;
    
    index_array = np.arange(0,p.size,1) ; #creating an array with original indexes
    #preparing loop
    i= 0 ;
    result = list() ; 
    indices = [0]*(min_support_points+1); 
    
    #looking for feature recursively
    while ((len(indices) >= min_support_points) & (i<=max_plane_number) & (p.size>=min_support_points)):   
        indices, model = perform_1_ransac_segmentation( p , _ksearch
            , sac_model
            , _distance_weight , _max_iterations , _distance_threshold) ; 
    
        #writting result if it it satisfaying
        if(len(indices) >= min_support_points) :
             result.append(   ((index_array[indices] + 1 ), model,sac_model) ) ;#should be # indices, model = seg.segment() 
            
            #prepare next iteration
        index_array = np.delete(index_array , indices);
        i+=1 ;
        p =  p.extract(indices, negative=True) ; #removing from the cloud the points already used for this plan
    return (result), p; 


