classdef Calibrator
    % CALIBRATOR represents calibration information for a calibrated camera
    % to transform raw digital images to absolute spectral photon luminance (in photons/nm/s/sr/m^2)
    %
    % Call sequence: elf -> elf_main1_perScene -> Calibrator
    %
    % See also: elf_main1_perScene, elf_info_load, elf_io_loaddng

    properties(SetAccess=immutable)
        CameraString(1, 1) string
        Height(1, 1) double
        Width(1, 1) double
        SpectralMethod(1, 1) string = "col"
        ProjectionInfo(1, 1) struct
        SerialNumber(1, 1) string = ""
    end

    properties(Access=protected)
        AbsoluteFactor
        AbsoluteMat
        VignettingMat
        Acf     % Aperture correction factor in new d850 calibration
        SpectralMatrix
        LinearisationTable
    end

    % methods in other files
    methods (Static)
        [info, srcs, warnings] = calculateBlackLevels(info, imgformat)
        % CALIBRATOR.CALCULATEBLACKLEVELS detects and loads dark images, if they are present. Results are directly written into info as a blackLevels field
    end
    
    %%%%%%%%%%%%%%%%%
    %% CONSTRUCTOR %%
    %%%%%%%%%%%%%%%%%
    methods
        function obj = Calibrator(camString, wh, spectralMethod, serialNumber)
            %CALIBRATOR Construct an instance of this class
            %   Detailed explanation goes here
            % Inputs:
            %   camString    - camera model (can be extracted from info.Model or infoSum.Model)
            %   wh           - width and height of images (can be extracted from info.Width and info.Height)
            %   method       - 'col' (default) - each channel of the output image represents the weighted mean over that pixels sensitivity function, assuming a flat spectrum over its full range
            %                  'colmat'        - solves the linear equation of all three channels to calculate a spectrum that is flat between 400-500/500-600/600-700nm and would create the same camera output
            %                                   This method theoretically creates the most interesting result, but is extremely sensitive to saturation in individual channels and can not be recommended for
            %                                   general use outside of laboratory situations - currently not implemented
            %                  'wb'            - simply applies the normal balance suggested by the camera (used if no calibration exists)
            %   serialNumber - a serial number string, mainly used for individual absolute/colour calibrations for Basler cameras

            if nargin>=4, obj.SerialNumber = serialNumber; end
            if nargin>=3 && spectralMethod~="", obj.SpectralMethod = spectralMethod; end
            Logger.log(LogLevel.INFO, 'Creating a Calibrator object for %s camera\n', camString)
            obj.CameraString = camString;
            obj.Width  = wh(1);
            obj.Height = wh(2);

            obj.ProjectionInfo = obj.loadProjectionInfo();
            obj = obj.loadCalib(); % load the absolute, spectral and vignetting correction
        end
    end

    %%%%%%%%%%%%%%%%%%%%
    %% PUBLIC METHODS %%
    %%%%%%%%%%%%%%%%%%%%
    methods
        function [im, conf, confFactors] = applyAbsolute(obj, im, info)
            %% Calibrator.applyAbsolute applies absolute calibration information to a raw photograph.
            % [im, conf, conffactors] = obj.applyAbsolute(im, info)
            % For a full calibration, obj.applySpectral must be applied afterwards (or after HDR calculation, if desired)
            %
            % Inputs:
            %   im          - M x N x 3 double, raw digital image (as obtained from elf_io_loaddng)
            %   info        - 1 x 1 struct, info structure, containing the exif information of the raw image file (created by elf_info_collect or elf_info_load)
            %                 info must contain a field .blackLevels, a 1 x 3 double, containing the black level for each colour channel, 
            %                 i.e. the number of counts that need to be subtracted from the raw counts, for this image, for each channel; 
            %                   obtained from calibration or dark images    
            % Outputs:
            %   im          - M x N x 3 double, calibrated digital image (in photons/nm/s/sr/m^2), but not spectrally corrected
            %   conf        - M x N x 3 double, an estimate of confidence based on noise for each pixel (used for HDR calculations)
            %   confFactors - 2 x 1 double, the combined calibration factor (correcting for exp/iso/apt) and the saturation limit (minus dark)

            % Extract camera parameters and calibration factors
            exp         = info.DigitalCamera.ExposureTime;      % exposure time in seconds
            iso         = info.DigitalCamera.ISOSpeedRatings;   % ISO speed
            apt         = info.DigitalCamera.FNumber;           % Aperture F-Stop
        
            % Apply calibration
            % Subtract the camera's black level (saturation level has to be taken into account later)
            im          = im - Calibrator.getBlackLevelMat(obj.Height, obj.Width, info.blackLevels);
            if ~isempty(obj.LinearisationTable)
                ctemplate = ones(size(im, 1), size(im, 2));
                c = cat(3, 1*ctemplate, 2*ctemplate, 3*ctemplate);
                im = sub_linearise(im, c);
            end

            conf        = im; % Use these raw values (after dark subtraction) to define every pixel's confidence: 
                              % In HDR calculation, each HDR pixel will be assigned the radiance value it holds in the image where it has the highest confidence 
            confFactors = obj.getSaturationLevel(info) - info.blackLevels(:)';  %% TODO: Unsure how this would have to be changed for linearised data; check through HDR calculation
        
            switch lower(obj.CameraString)
                case {"aca4096-40uc", "basler aca4096-40uc"}
                    % GAIN/EXP 2025 calibration
                    gain = round(10*log10((iso/100).^2)); % gain is saved as ISO -> calculated back to gain
                    gainfac = db2mag(gain); % calculate gain muliplication factor
                    settingFactor  = exp * gainfac;

                case {'nikon d800e', 'nikon d810', 'nikon z 6'}
                    % ISO/EXP/APT 2016 calibration
                    % correct for uneven aperture spacing, and calculate aperture "area" 
                    ev_num      = round(log(apt) / log(sqrt(2)) * 3);
                    apt_even    = sqrt(2).^(ev_num/3);
                    aparea      = pi * (4./apt_even).^2.292; % 2.292 was determined during 2017 aperture calibration
                    settingFactor  = exp * iso * aparea;
                    
                case 'nikon d850'
                    % ISO/EXP/APT 2021 calibration
                    acf = obj.Acf(obj.Acf(:, 1)==apt, 2);
                    settingFactor  = exp * iso * acf;
                
                otherwise
                    settingFactor  = exp * iso / apt.^2;
            end   
            
            % correct for exposure time, ISO setting (gain) and aperture
            im = im ./ settingFactor ./ obj.AbsoluteMat;            % counts per second per ISO per aperture
            
            % correct for vignetting
            switch apt
                case {1.4, 3.5, 4, 4.5, 4.8, 5.6} % 1.4 is for Basler camera
                    apInd = 1; % treat as aperture 3.5 for vignetting
                case {8, 9, 10, 11, 14}
                    apInd = 2; % treat as aperture 8 for vignetting
                case 22
                    apInd = 3; % treat as aperture 22 for vignetting
                otherwise
                    error('Aperture %g currently not supported.', apt);
            end
            im = im ./ obj.VignettingMat{apInd};

            function x_lin = sub_linearise(x, c)
                % Calculate linear radiance values x_lin from dark-corrected counts x, with colour channel c

                lut_counts = obj.LinearisationTable(:, 1);
                lut_lin    = obj.LinearisationTable(:, 2:end);

                x = min(max(x, 0), max(lut_counts));
                x_lin = nan(size(x));
                for ich = 1:3
                    sel = c==ich;
                    x_lin(sel) = interp1(lut_counts, lut_lin(:, ich), x(sel));
                end
            end
        end


        function im = applySpectral(obj, im, info)
            %% Calibrator.applySpectral applies absolute spectral information to a pre-calibrated photograph.
            % im = obj.applySpectral(im, info)
            % For a full calibration, this should be applied after obj.applyAbsolute has been applied
            %
            % Inputs:
            %   im          - M x N x 3 double, calibrated digital image (as obtained from Calibrator)
            %   info        - 1 x 1 struct, info structure, containing the exif information of the raw image file (created by elf_info_collect or elf_info_load)
            %       
            % Outputs:
            %   im          - M x N x 3 double, calibrated digital image (in photons/nm/s/sr/m^2)

            if lower(obj.CameraString) == "basler aca4096-40uc" || lower(obj.CameraString) == "aca4096-40uc"
                % For this camera, spectral calibration is included in the absolute calibration
                return
            end

            wb_multipliers  = (info.AsShotNeutral).^-1;
            wb_multipliers  = wb_multipliers/wb_multipliers(2); % normalise to green channel
            
            switch obj.SpectralMethod
                case 'colmat'
                    error("'colmat' spectral method is no longer supported")                    
                case 'col'
                    % This is the current default:  Scale individual channels so each one represents the weighted average spectral photon radiance
                    %                               over that pixels sensitivity
                    if isempty(obj.SpectralMatrix)
                        % If there is no calibration, use camera manufacturer's white balance multipliers
                        col = 1./wb_multipliers;
                    else
                        col = obj.SpectralMatrix;
                    end
                    im(:, :, 1) = im(:, :, 1) / col(1);
                    im(:, :, 2) = im(:, :, 2) / col(2);
                    im(:, :, 3) = im(:, :, 3) / col(3);
                    
                case 'wb'
                    % Apply the "As shot" white balance to correct for sensitivity differences in R, G and B pixels
                    im(:, :, 1)     = im(:, :, 1) * wb_multipliers(1);
                    im(:, :, 2)     = im(:, :, 2) * wb_multipliers(2);
                    im(:, :, 3)     = im(:, :, 3) * wb_multipliers(3);                    
            end
        end
    end


    %%%%%%%%%%%%%%%%%%%%%%%%
    %% LOADING FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%
    methods(Hidden, Access=protected)
        function obj = loadCalib(obj)
            %% Calibrator.loadCalib loads the absolute, spectral and vignetting calibration matrix for this Calibrator object from file
            % The matrices are stored in obj.VignettingMat and obj.AbsoluteMat, from where it is later used in obj.applyAbsolute
            % The correct spectral matrix (depending on obj.SpectralMethod) is extracted and stored in obj.SpectralMatrix, from where it is later used in obj.applySpectral

            Logger.log(LogLevel.INFO, "\tCreating/loading calibration correction matrices\n")
            para = elf_para({}, "noenv");

            % determine which file to load
            switch lower(obj.CameraString)
                case {"nikon d800e", "nikon d810", "nikon z 6"}
                    camstring = "nikon d810"; % use d810 calibration for all these models
                case {"aca4096-40uc", "basler aca4096-40uc"}
                    camstring = "basler aca4096-40uc";
                otherwise
                    camstring = lower(obj.CameraString);
            end

            switch camstring
                case {"nikon d800e", "nikon d810", "nikon z 6"}
                    
                    % 1. ISO/EXP/APT 2016 calibration
                    TEMP    = load(fullfile(para.fh.Paths.calibfolder, camstring, "absolute.mat"));
                    obj.AbsoluteFactor = TEMP.wlcf;
                    
                    % 2. Vignetting
                    I_info = struct("Height", obj.Height, "Width", obj.Width, "SamplesPerPixel", 3, "FocalLength", 8, "Model", obj.CameraString);
                    proj = Projector.fromInfoStructs(I_info, obj.ProjectionInfo); %Iinfo needs Height, Width, SamplesPerPixel, FocalLength
                    obj.VignettingMat = Calibrator.getVignMat(camstring, obj.Height, obj.Width, proj);
        
                case "nikon d850"
        
                    % 1. ISO/EXP/APT calibration
                    TEMP    = load(fullfile(para.fh.Paths.calibfolder, camstring, "absolute.mat"));
                    obj.Acf = TEMP.acf;
                    obj.AbsoluteFactor = TEMP.wlcf;
                                
                    % 2. Vignetting
                    I_info = struct("Height", obj.Height, "Width", obj.Width, "SamplesPerPixel", 3, "FocalLength", 8, "Model", obj.CameraString);
                    proj = Projector.fromInfoStructs(I_info, obj.ProjectionInfo); %Iinfo needs Height, Width, SamplesPerPixel, FocalLength
                    obj.VignettingMat = Calibrator.getVignMat("nikon d810", obj.Height, obj.Width, proj);
                    
                case "basler aca4096-40uc"
                    % absolute calibration is dependent on camera serial number; if not available, or no calibration exists for this one, use standard

                    % 1. ISO/EXP/APT calibration
                    if obj.SerialNumber==""
                        fname = fullfile(para.fh.Paths.calibfolder, camstring, "absolute.mat");
                    else
                        fname = fullfile(para.fh.Paths.calibfolder, camstring, "absolute_"+obj.SerialNumber+".mat");
                        if ~exist(fname, "file")
                            fname = fullfile(para.fh.Paths.calibfolder, camstring, "absolute.mat");
                        end
                    end

                    TEMP = load(fname);
                    obj.AbsoluteFactor = TEMP.wlcf; % This includes the spectral calibration for this camera type
                                
                    % 2. Vignetting
                    I_info = struct("Height", obj.Height, "Width", obj.Width, "SamplesPerPixel", 3, "FocalLength", 1.8, "Model", obj.CameraString);
                    proj = Projector.fromInfoStructs(I_info, obj.ProjectionInfo); %Iinfo needs Height, Width, SamplesPerPixel, FocalLength
                    obj.VignettingMat = Calibrator.getVignMat(camstring, obj.Height, obj.Width, proj);

                    % 3. Linearisation
                    fname = fullfile(para.fh.Paths.calibfolder, camstring, "linearity.mat");
                    temp = load(fname, "lut", "ch_corr_linearity");
                    obj.LinearisationTable = [zeros(1, size(temp.lut, 2));
                                              temp.lut(:, 1) 10.^temp.lut(:, 2:end)];

                otherwise
                    % For an unknown camera, use no calibration correction; an uncalibrated image is better than none
        
                    % 1. ISO/EXP/APT calibration
                    obj.AbsoluteFactor = [1 1 1];
                                
                    % 2. Vignetting
                    I_info = struct("Height", obj.Height, "Width", obj.Width, "SamplesPerPixel", 3, "FocalLength", 8, "Model", obj.CameraString);
                    proj = Projector.fromInfoStructs(I_info, obj.ProjectionInfo); %Iinfo needs Height, Width, SamplesPerPixel, FocalLength
                    obj.VignettingMat = Calibrator.getVignMat("nikon d810", obj.Height, obj.Width, proj);
        
                    warning("No intensity calibration available for this camera (%s) ", obj.CameraString);
            end

            % pre-calculate mats for faster calibration later
            Logger.log(LogLevel.INFO, "\tCreating/loading absolute sensitivity correction matrix\n")
            obj.AbsoluteMat = Calibrator.getAbsoluteMat(obj.CameraString, obj.Height, obj.Width, obj.AbsoluteFactor);

            Logger.log(LogLevel.INFO, "\tCreating/loading spectral correction matrix\n")

            % load from file, and extract the right matrix depending on obj.SpectralMethod
            switch obj.SpectralMethod
                case "colmat" % Full deconvolution of channels to reconstruct a spectrum that is flat between 400-500, 500-600 and 600-700 nm
                    error("'colmat' spectral method is no longer supported")
                case "col" % Scale individual channels so each one represents the weighted average spectral photon radiance over that pixels sensitivity
                    obj.SpectralMatrix = obj.getCol(camstring);
                    Logger.log(LogLevel.DEBUG, '\t\tCalculating colour matrix\n')
                    switch camstring
                        case "basler aca4096-40uc"
                            % For this camera, spectral calibration is included in the absolute calibration
                            obj.SpectralMatrix = [];                                        
                        otherwise
                            para  = elf_para;
                            fname = fullfile(para.fh.Paths.calibfolder, lower(camstring), 'rgb_calib.mat');
                            if isfile(fname)
                                TEMP    = load(fname, 'col');            
                                obj.SpectralMatrix     = TEMP.col;
                            else
                                obj.SpectralMatrix     = [];
                            end                    
                    end
                case "wb"
                    % Uses the white balance multipliers from each file's exif information
            end
        end


        function satLevel = getSaturationLevel(obj, info)
            %% Calibrator.getSaturationLevel returns the saturation level for this camera (before dark correction)

            switch lower(obj.CameraString)
                case {'nikon d800e', 'nikon d810', 'nikon z 6', 'nikon d850'}
                    satLevel = 15520; % 15992 was found in d810 calibration, 15520 is the black value in EXIF file
                case {"aca4096-40uc", "basler aca4096-40uc"}
                    satLevel = 4091;
                otherwise
                    satLevel = 0.95*info.SubIFDs{1}.WhiteLevel(1); % white level, this should corresponds to a reasonable saturation level
            end
        end


        function ProjectionInfo = loadProjectionInfo(obj)
            %% Calibrator.loadProjectionInfo loads the spatial calibration information for this Calibrator object
            % All information is currently stored in this function, but could conceivably be stored in a file instead
            % Note that all information is loaded by camera type, even though it depends on the lens, of course! This is a shorthand to refer to our
            % calibrated camera/lens combinations, because lens information is rarely stored in EXIF information 

            ProjectionInfo.Type = "equisolid";
            ProjectionInfo.PixPerMM = [];
            ProjectionInfo.WCorr = 0; % correction for centre in width (obtained from calibration for imperfect lens)
            ProjectionInfo.HCorr = 0; % correction for centre in height (obtained from calibration for imperfect lens)
            ProjectionInfo.RCorr = 1; % correction multiplier for R (obtained from calibration for imperfect lens)
            ProjectionInfo.ChipHeight = 24.0; % chip height in mm
            ProjectionInfo.ChipWidth = 35.9; % chip width in mm
            ProjectionInfo.K = 0;
            
            switch lower(obj.CameraString)
                case 'nikon d800e'
                    ProjectionInfo.RCorr = 1.02;
                    
                case 'nikon d810'

                case 'nikon d850'
                    ProjectionInfo.ChipHeight = 23.9; % chip height in mm
                    ProjectionInfo.ChipWidth = 35.9; % chip width in mm

                case 'nikon d3x'
                    ProjectionInfo.WCorr = -7;
                    ProjectionInfo.HCorr = 7;
                    ProjectionInfo.RCorr = 1.02;
                    
                case 'nikon z 6'
                    ProjectionInfo.ChipHeight = 23.9; % chip height in mm
                    ProjectionInfo.ChipWidth = 35.9; % chip width in mm

                case 'canon eos-1ds mark ii'
                    ProjectionInfo.WCorr = -13.5;
                    ProjectionInfo.HCorr = -13.5;
                    ProjectionInfo.RCorr = 0.96;
                    ProjectionInfo.ChipHeight = 24.0; % chip height in mm
                    ProjectionInfo.ChipWidth = 36.0; % chip width in mm

                case 'nikon d5300'
                    ProjectionInfo.RCorr = 1.35;
                    ProjectionInfo.ChipHeight = 15.6; % chip height in mm
                    ProjectionInfo.ChipWidth = 23.5; % chip width in mm

                case {"basler aca4096-40uc", "aca4096-40uc"}
                    ProjectionInfo.K = -0.22918;
                    ProjectionInfo.PixPerMM = 1/0.00345;
                    ProjectionInfo.Type = "general";
                    ProjectionInfo.RCorr = 1.00937; % correction multiplier for R (obtained from calibration for imperfect lens)
                    ProjectionInfo.ChipHeight = 0; % chip height in mm
                    ProjectionInfo.ChipWidth = 0; % chip width in mm

                otherwise
                    warning('No spatial calibration available for this camera (%s) and lens. Assuming perfect equisolid projection on full size chip', obj.CameraString);                    
            end
        end
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% STATIC LOADING FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods (Static)
        function blackLevelMat = getBlackLevelMat(height, width, blackLevels)            
            %% Calibrator.getBlackLevelMat loads or calculates the black level correction matrix for this image width and image height.
            % This is called during obj.applyAbsolute with the blackLevels for one particular frame.
            % The matrix is saved in a static class variable, so that at the next frame/dataset, it does not
            % need to be re-loaded from file, as long as image width and height stay the same.
            
            persistent storeBLM;
            persistent storedBLMName;
            
            blmname               = sprintf('%d_%d', height, width);
            
            if strcmp(blmname, storedBLMName) && ~isempty(storeBLM)
                blackLevelMat = storeBLM;
            else
                blackLevelMat = ones(height, width, 3);
                storeBLM      = blackLevelMat;
                storedBLMName = blmname;
            end

            blackLevelMat(:, :, 1) = blackLevels(1);
            blackLevelMat(:, :, 2) = blackLevels(2);
            blackLevelMat(:, :, 3) = blackLevels(3);
        end


        function absMat = getAbsoluteMat(camstring, height, width, absoluteFactor)
            %% Calibrator.getAbsoluteMat loads or calculates the absolute sensitivity correction matrix for this camera type, image width and image height.
            % This is called during obj.loadAbsoluteCalibration.
            % The matrix is saved in a static class variable, so that the next time a Calibrator object for the same camera is created, it does not
            % need to be re-loaded from file.
            
            persistent storeWLCM;
            persistent storedWLCMName;
            
            wlcmname             = sprintf('%s_%d_%d', camstring, height, width);
            
            if strcmp(wlcmname, storedWLCMName) && ~isempty(storeWLCM)
                Logger.log(LogLevel.DEBUG, '\t\tUsing stored matrix\n')
                absMat           = storeWLCM;
            else
                Logger.log(LogLevel.DEBUG, '\t\tCalculating new matrix\n')
                absMat = ones(height, width, 3);
                absMat(:, :, 1) = absoluteFactor(1);
                absMat(:, :, 2) = absoluteFactor(2);
                absMat(:, :, 3) = absoluteFactor(3);
                storeWLCM        = absMat;
                storedWLCMName   = wlcmname;
            end
        end


        function vignMat = getVignMat(camstring, height, width, proj)
            %% Calibrator.getVignMat loads or calculates the vignetting matrix for this camera type, image width and image height.
            % This is called during obj.loadAbsoluteCalibration.
            % The matrix is saved in a static class variable, so that the next time a Calibrator object for the same camera is created, it does not
            % need to be re-loaded from file.
            %
            % Saving to a file and loading when needed has been tested and takes longer than recalculating on ELFPC (10s v 3s)
            
            persistent storedVign;
            persistent storedVignName;
            
            vignname = sprintf('%s_%d_%d', camstring, height, width);
            
            if strcmp(vignname, storedVignName) && ~isempty(storedVign)
                Logger.log(LogLevel.DEBUG, '\t\tUsing stored matrix\n')
                vignMat    = storedVign;
            else
                Logger.log(LogLevel.DEBUG, '\t\tCalculating new matrix\n')

                % Calculate excentricity and vignetting correction, and store in persistents
                warning("This new vignetting calculation has not been tested!")
                [y, x]  = meshgrid(1:width, 1:height);       % x/y positions of all points in the image
                exc     = real(proj.pix2theta(y, x));

                % Calculate vignetting correction
                para    = elf_para;
                fname   = fullfile(para.fh.Paths.calibfolder, lower(camstring), 'vign_calib.mat');
                if isfile(fname)
                    TEMP = load(fname); % holds pf, fitted vignetting-correction function
                    pf = TEMP.pf;
                else
                    warning('No vignetting calibration exists for this camera; not correcting for vignetting');
                    pf = cat(3, zeros(3, 3), zeros(3, 3), zeros(3, 3), ones(3, 3));
                end
                
                vignMat = cell(size(pf, 1), 1);
                for iapt = 1:size(pf, 1)
                    fr      = sub_feval(pf(iapt, 1, :), exc) / sub_feval(pf(iapt, 1, :), 0);
                    fg      = sub_feval(pf(iapt, 2, :), exc) / sub_feval(pf(iapt, 2, :), 0);
                    fb      = sub_feval(pf(iapt, 3, :), exc) / sub_feval(pf(iapt, 3, :), 0);
                    vignMat{iapt} = cat(3, fr, fg, fb);
                end
                
                storedVign = vignMat;
                storedVignName = vignname;
            end

            function y = sub_feval(fun, x)
                y = fun(1)*x.^3 + fun(2)*x.^2 + fun(3)*x + fun(4);
                y(y<0) = NaN;
            end
        end
        
        
        function col = getCol(camstring)
            %% Calibrator.getCol loads or calculates the color correction vector for this camera type.
            % This is called during obj.loadSpectralCalibration if obj.SpectralMethod is "col".
            
            Logger.log(LogLevel.DEBUG, '\t\tCalculating colour matrix\n')
            switch camstring
                case "basler aca4096-40uc"
                    % For this camera, spectral calibration is included in the absolute calibration
                    col = 1;
                                
                otherwise
                    para  = elf_para;
                    fname = fullfile(para.fh.Paths.calibfolder, lower(camstring), 'rgb_calib.mat');
                    if isfile(fname)
                        TEMP    = load(fname, 'col');            
                        col     = TEMP.col;
                    else
                        col     = [];
                    end
            
            end
        end
    end
end

