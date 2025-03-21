import json
import h5py
import os
import numpy as np
from numpy import matlib, linalg
from PIL import Image

def elf_io_readwrite(para:dict, action:str, fname:str=""):
        """Read/write common ELF data structures. Syntax depends on action, see individual entries below.

        Args:
            para (dict): Parameter dictionary, obtained from elf_io_readwrite([], "loadpara", fname).
            action (str): Which load action to perform; see below for valid values.
            fname (str, optional): Filename; needs to be a full path for action="loadpara", or a scene name for other actions (e.g. "scene001")

        Returns:
            Return image or dict (depending on action)
        """

        if action == "loadpara":
                # load the para structure from the infosum file for this environment
                # para = elf_io_readwrite([], "loadpara", fname)
                with open(fname) as f:
                        data = json.load(f)
                return data["para"]
                                
        if action == "loadinfosum":
                # load the infosum structure for this environment
                # para = elf_io_readwrite(para, "loadinfosum")
                # OR
                # para = elf_io_readwrite([], "loadinfosum", "scene001")
                if para:
                        fname = para["paths"]["fname_infosum_json"]
                with open(fname) as f:
                        data = json.load(f)
                return data["infosum"]
        
        elif action == "loadHDR_mat":
                # load the HDR image for one scene from the mat file (calibrated)
                # im = elf_io_readwrite(para, "loadHDR_mat", "scene001")
                (_, f) = os.path.split(fname)
                fname  = os.path.join(para["paths"]["datapath"], para["paths"]["scenefolder"], f+".mat")
                with h5py.File(fname, "r") as f:
                        data = f.get("varinput")
                        return np.transpose(np.array(data), (2, 1, 0))
                
        elif action == "loadHDR_tif":
                # load the HDR image for one scene from the tif file (uncalibrated)
                # im = elf_io_readwrite(para, "loadHDR_tif", "scene001")
                
                (_, f) = os.path.split(fname)
                fname  = os.path.join(para["paths"]["datapath"], para["paths"]["scenefolder"], f+".tif")
                return np.array(Image.open(fname))
                
        elif action == "loaddiag_tif":
                # load the diagnostic image for one scene from the tif file (uncalibrated)
                # R: saturation, G: low signal, B: movement between exposures
                # im = elf_io_readwrite(para, "loaddiag_tif", "scene001")
                
                (_, f) = os.path.split(fname)
                fname  = os.path.join(para["paths"]["datapath"], para["paths"]["diagfolder"], f+".tif")
                return np.array(Image.open(fname))
        
        elif action == "loadfilt_mat":
                # load the filtered HDR image for one scene from a mat file
                # im = elf_io_readwrite(para, "loadfilt_mat", "scene001")

                (_, f) = os.path.split(fname)
                fname  = os.path.join(para["paths"]["datapath"], para["paths"]["filtfolder"], f+"_filt.mat")
                with h5py.File(fname, "r") as f:
                        data = f.get("varinput")
                        return [np.transpose(np.array(f[x]), (2, 1, 0)) for x in data[0]]
        
        elif action == "loadstokes_mat":
                # load the filtered Stokes vector images for one scene from a mat file
                # im = elf_io_readwrite(para, "loadstokes_mat", "scene001")

                ## TODO: fix once Stokes data format has been finalised
                
                (_, f) = os.path.split(fname)
                fname  = os.path.join(para["paths"]["datapath"], para["paths"]["filtfolder"], f+"_stokes.mat")
                with h5py.File(fname, "r") as f:
                        data = f.get("varinput")
                        return np.array(data)

        else:
                raise(Exception(f"Unknown value for parameter action: {action}"))
        
  
def elf_io_correctdng(lin_im:np.ndarray, meta_info:dict=[], method:str="default", maxval:float=0) -> np.ndarray:
        """ELF_IO_CORRECTDNG takes a linear DNG image (uint16 values), converts its
           colour space to sRGB and gamma-corrects it for "normal" display (assuming normal white balance is set). 
           Algorithm adapted from Rob Sumner (2014) "Processing RAW Images in
           MATLAB", http://users.soe.ucsc.edu/~rcsumner/rawguide/RAWguide.pdf

        Args:
            lin_im (np.ndarray): linear image to be displayed, can be float, uint8, uint16
            meta_info (dict, optional): exif info dict, only needed for the ColorMatrix2 value, so can be infosum. Defaults to the standard D800 colour matrix.
            method (str, optional): determines what value the image is normalised to:    
                                "bitdepth" : default method, normalise depending on maximum of lin_im 
                                             (1 if max<1, 2^8 if max<2^8, 2^16 if max<2^16, max otherwise)
                                "max"      : normalise to the maximum of lin_im
                                "maxval"   : normalise to the input argument maxval
                                "bright"/"maxbright"/"maxvalbright" : use a bright version of gamma correction
            maxval (float, optional): Normalisation value for the "maxval" method

        Returns:
            np.ndarray: Corrected image
        """

        def sub_apply_cmatrix(im, cmatrix):
                # CORRECTED = sub_apply_cmatrix(IM, CMATRIX)
                #
                # Applies CMATRIX to RGB input IM. Finds the appropriate weighting of the
                # old color planes to form the new color planes, equivalent to but much
                # more efficient than applying a matrix transformation to each pixel.

                if im.shape[2]!=3:
                        raise(ValueError("Apply cmatrix to RGB image only."))

                r = cmatrix[0,0]*im[:,:,0:1] + cmatrix[0,1]*im[:,:,1:2] + cmatrix[0,2]*im[:,:,2:3]
                g = cmatrix[1,0]*im[:,:,0:1] + cmatrix[1,1]*im[:,:,1:2] + cmatrix[1,2]*im[:,:,2:3]
                b = cmatrix[2,0]*im[:,:,0:1] + cmatrix[2,1]*im[:,:,1:2] + cmatrix[2,2]*im[:,:,2:3]
                return np.concatenate((r, g, b), 2)


        def sub_srgbGamma(im):
                # im = sub_srgbGamma(im)
                #
                # Applies  a standard (inverse) sRGB gamma correction to an RGB image.
                # Assumes input values are scaled between 0 and 1, returns a similar range.
                
                nl          = im > 0.0031308  # anything > a count of ~205
                im[nl]      = 1.055 * im[nl]**(1/2.4) - 0.055
                im[~nl]     = 12.92 * im[~nl]
                return im

        def sub_rgb2gray(im):
                # Turns an RGB image into a grayscale image using matlab default values
                return 0.298936021293775 * im[:, :, 0] + 0.587043074451121 * im[:, :, 1] + 0.114020904255103 * im[:, :, 2] 
        

        if (not meta_info) or (len(meta_info["ColorMatrix2"]) == 1 and meta_info["ColorMatrix2"] == 0):
                meta_info["ColorMatrix2"] = np.array([0.7866, -0.2108, -0.0555, -0.4869, 1.2483, 0.2681, -0.1176, 0.2069, 0.7501])
                print("Warning: io_correctdng: No valid colour correction matrix provided. Using standard D800 matrix.")

        ## Parameters
        # create conversion matrices
        rgb2xyz  = np.array([[.4124564, .3575761, .1804375], [.2126729, .7151522, .0721750], [.0193339, .1191920, .9503041]])  # from Adobe sRGB to XYZ colour space
        xyz2cam  = np.reshape(meta_info["ColorMatrix2"], (3, 3)) # from XYZ to camera colour space
        rgb2cam  = xyz2cam @ rgb2xyz                      # from sRGB to camera colour space
        rgb2cam  = rgb2cam / np.transpose(matlib.repmat(np.sum(rgb2cam,1), 3, 1))  # normalize rows to 1
        cam2rgb  = linalg.inv(rgb2cam)                             # from camera to sRGB colour space

        ## 1) Normalise
        lin_im   = lin_im.astype("float")
        if method in ["default", "bitdepth", "bright"]:
                if np.nanmax(lin_im) <= 1:
                        mv = 1
                elif np.nanmax(lin_im) <= 2^8:
                        mv = 2^8
                elif np.nanmax(lin_im) <= 2^16:
                        mv = 2^16 
                else:
                        mv = np.nanmax(lin_im)        
        elif method in ["max", "maxbright"]:
                mv   = np.nanmax(lin_im)
        elif method in ["maxval", "maxvalbright"]:
                mv = maxval
        else:
                raise(ValueError(f"Unknown correctdng method: {method}"))
        lin_im   = lin_im / mv

        ## 2) Colour Space Conversion to sRGB
        lin_srgb = sub_apply_cmatrix(lin_im, cam2rgb);     # apply conversion matrix
        lin_srgb = np.clip(lin_srgb, 0, 1);                # Always keep image clipped b/w 0-1

        ## 3) Gamma correction
        im       = sub_srgbGamma(lin_srgb)
        if method=="bright" or method=="maxvalbright" or method=="maxbright":
                ## 3) Gamma correction (bright version)
                grayim      = sub_rgb2gray(lin_srgb)
                grayscale   = 0.25/np.nanmean(grayim)
                bright_srgb = np.clip(lin_srgb*grayscale, None, 1)
                im          = sub_srgbGamma(bright_srgb)

        return im

        
