classdef Projector
    % PROJECTOR provides methods to change the projection of fisheye images
    %
    % Each Projector object represents one fisheye projection (defined by the projection type, image size, focal length and chip pixel density), 
    % and a corresponding equirectangular projection (defined by the azimuth and elevation vectors describing its two dimensions).
    % When an image is projected into a different fisheye projection (i.e. generally, a different type or image size), a new Projector object is generated.
    %
    % Call sequence: elf -> elf_main1_perScene -> Projector
    %
    % See also: Calibrator

    properties (SetAccess=immutable)
        Size(1,3) double             % [height, width, number of channels] of the original fisheye image
        ProjectionType(1,1) string   % type of fisheye projection in the original image, e.g. "equisolid"
        ErAzi(1,3) double            % azimuth vector (as [start step end]) for the equirectangular projection; e.g. [-90, 0.1, 90]
        ErEle(1,3) double            % elevation vector (as [start step end]) for the equirectangular projection; e.g. [90, -0.1, -90]
        MidPoint(1,2) double         % image centre in h/w
        PixPerMM(1,1) double         % pixel density (assumed to be equal in both dimensions) of the chip
        CorrFocalLength(1,1) double  % the "effective" focal length (real focal length * a correction factor to match the observed image circle)
    end

    properties (Dependent,Transient)
        RectSize(1,3) double         % [height, width, number of channels] size of the equirectangular image
    end
    
    methods
        function s = get.RectSize(obj)
            % GET function for the RectSize property
            s = [floor((obj.ErEle(3)-obj.ErEle(1))/obj.ErEle(2)+1), floor((obj.ErAzi(3)-obj.ErAzi(1))/obj.ErAzi(2)+1), obj.Size(3)];
        end
    end

    %%%%%%%%%%%%%%%%%%
    %% CONSTRUCTORS %%
    %%%%%%%%%%%%%%%%%%
    methods
        function obj = Projector(imSize, projectionType, erAzi, erEle, midPoint, pixPerMM, corrFocalLength)
            % PROJECTOR Construct an instance of this class directly
            % obj = Projector(imSize, projectionType, [erAzi, erEle, midPoint, pixPerMM, corrFocalLength])
            %
            % See also: Projector.fromInfoStructs, Projector.fromImageCircle

            arguments
                imSize (1,3) double
                projectionType (1,1) string
                erAzi (1,3) double = [-90, 0.1, 90]
                erEle (1,3) double = [90, -0.1, -90]
                midPoint (1,2) double = [(imSize(1)+1)/2, (imSize(2)+1)/2]
                pixPerMM (1,1) double = NaN
                corrFocalLength (1,1) double = 8
            end

            obj.Size = imSize;
            obj.ProjectionType = projectionType;
            obj.ErAzi = erAzi;
            obj.ErEle = erEle;
            obj.MidPoint = midPoint;
            obj.CorrFocalLength = corrFocalLength;

            if isnan(pixPerMM)
                % set pixPerMM to create a filled image
                shortSide = min(imSize(1:2));
                imageCircleRadius = obj.theta2r(90);
                pixPerMM = (shortSide-1) / 2 / imageCircleRadius; % shortSide-1 is needed to put 90/-90 degrees exactly on the middle (not the outer edge) of the outermost pixel
            end
            obj.PixPerMM = pixPerMM;
        end
    end

    methods(Static)
        function obj = fromInfoStructs(I_info, projInfo, erAzi, erEle)
            %PROJECTOR.FROMINFOSTRUCTS Construct an instance of this class from info structs
            %
            % Inputs:
            %   I_info   - exif information structure, needed fields: Height, Width, SamplesPerPixel, FocalLength
            %   projInfo - additional projection information that is not included in EXIF information, or needs to be calibrated
            %                 (obtained from Calibrator object), needed fields: 
            %                   .ChipWidth - chip width in mm 
            %                   .ChipHeight - chip height in mm 
            %                   .Type - type of fisheye projection in the original image, e.g. "equisolid"
            %                   .RCorr - correction multiplier for R (obtained from calibration for imperfect lens)
            %                   .WCorr - correction for centre in height (obtained from calibration for imperfect lens)
            %                   .HCorr - correction for centre in width (obtained from calibration for imperfect lens)
            %   erAzi, erEle - output angle ranges defining the desired grid of the projected images (default [-90, 0.1, 90], and [90, -0.1, -90])

            arguments
                I_info (1,1) struct
                projInfo (1,1) struct
                erAzi (1,3) double = [-90, 0.1, 90]
                erEle (1,3) double = [90, -0.1, -90]
            end

            Logger.log(LogLevel.INFO, 'Creating a Projector object for %s camera\n', I_info.Model{1})

            imSize = [I_info.Height, I_info.Width, I_info.SamplesPerPixel];
            projectionType = projInfo.Type;

            shortSide = min(imSize(1:2));
            chipShortSide = min([projInfo.ChipHeight projInfo.ChipWidth]);

            pixPerMM = shortSide / chipShortSide;
            corrFocalLength = I_info.FocalLength * projInfo.RCorr;   
            midPoint = [(imSize(1)+1)/2+projInfo.HCorr; (imSize(2)+1)/2+projInfo.WCorr];        % centre of image

            obj = Projector(imSize, projectionType, erAzi, erEle, midPoint, pixPerMM, corrFocalLength);   
        end

        function obj = fromImageCircle(oldProj, imageCircleRadius_deg)
            %PROJECTOR.FROMIMAGECIRCLE Construct an instance of this class by cropping an old class to a certain image circle radius (in degrees)
            %
            % Also see: Projector.fromInfoStructs, Projector
            
            arguments
                oldProj (1,1) Projector
                imageCircleRadius_deg (1,1) double
            end

            d_pix = ceil(2*oldProj.theta2r(imageCircleRadius_deg)*oldProj.PixPerMM);
            imSize = [d_pix, d_pix, oldProj.Size(3)];
            midPoint = [(imSize(1)+1)/2; (imSize(2)+1)/2];
           
            obj = Projector(imSize, ...
                            oldProj.ProjectionType, ...
                            oldProj.ErAzi, ...
                            oldProj.ErEle, ...
                            midPoint, ...
                            oldProj.PixPerMM, ...
                            oldProj.CorrFocalLength);
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% FISHEYE PROJECTION CORE FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % These functions convert the angle theta of a point against the optical axis to a radial distance R in mm on the chip, and vice versa

    methods
        function theta_deg = r2theta(obj, R_mm)
            %PROJECTOR.R2THETA transforms R (the radial excentricity of a point on the chip in mm) to theta (the excentricity angle in degrees)
            switch obj.ProjectionType
                case {"equisolid", "default"}
                    theta_deg = 2 * asind(R_mm / 2 / obj.CorrFocalLength);
                case "equidistant"
                    theta_deg = rad2deg(R_mm / obj.CorrFocalLength);
                case "stereographic"
                    theta_deg = 2 * atand(R_mm / 2 / obj.CorrFocalLength);
                case "orthographic"
                    theta_deg = asind(R_mm / obj.CorrFocalLength);
                otherwise
                    error('Unknown method')
            end
        end

        function R_mm = theta2r(obj, theta_deg)
            %PROJECTOR.THETA2R transforms theta (a point's excentricity angle in degrees) to R (the radial excentricity on the chip in mm)
            switch obj.ProjectionType
                case {"equisolid", "default"}
                    R_mm = 2 * obj.CorrFocalLength * sind(theta_deg / 2);
                case "equidistant"
                    R_mm = obj.CorrFocalLength * deg2rad(theta_deg);
                case "stereographic"
                    R_mm = 2 * obj.CorrFocalLength * tand(theta_deg / 2);
                case "orthographic"
                    R_mm = obj.CorrFocalLength * sind(theta_deg);
                otherwise
                    error('Unknown method')
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% PIXEL PROJECTION FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % These functions translate pixel position between fisheye image pixels (PIX: w/h), equirectangular image angles (RECT: azi/ele) and 3D cartesian vector coordinates (CART: X/Y/Z)
    %
    % Available functions:
    %   PIX2CART
    %   PIX2RECT
    %   PIX2PIX
    %   CART2PIX
    %   RECT2PIX
    %
    % Not available:
    %   CART2RECT -> use built-in cart2sph and rad2deg
    %   RECT2CART -> use built-in sph2cart and deg2rad

    % Input/Outputs for all methods
    %   w, h     - x/y image coordinates in pixels, e.g. defining the desired grid of a projected image along image width and height, respectively
    %   X, Y, Z  - cartesian coordinates in arbitrary units, e.g. on a unit sphere surrounding the camera
    %   azi, ele - azimuth/elevation in degrees
    %   rotation - angle (in degrees) by which the image needs to be rotated clockwise around the optical axis to achieve the desired orientation (Use 90 or -90 for portrait images)
    
    % optAx is a ViewDir object or the [az el] in degrees of the optical axis, e.g. 
    %   [0 90] for an upward-facing image
    %   [0 0] for an East-facing image
    %   [90 0] for an North-facing image
    % rotAroundOptAx is the CW angle (in degrees) by which the image must be rotated 
    %   around its optical axis to have the top facing up 
    %   (or westward for an upward-facing image)

    methods        
        % function [X, Y, Z] = pix2cart(obj, w, h, rotation)
        function [X, Y, Z] = pix2cart(obj, w, h, optAx, rotAroundOptAx)
            % PIX2CART translates w/h pixel positions into X,Y,Z on a unit sphere
            %
            % [X, Y, Z] = obj.pix2cart(obj, [w, h, optAx, rotAroundOptAx])
            
            arguments
                obj (1,1) Projector
                w double = []
                h double = []
                optAx = ViewDir.H
                rotAroundOptAx (1,1) double = 0
            end

            if isempty(optAx), optAx = ViewDir.H; end
            if isa(optAx, "ViewDir"), optAx = optAx.AzEl; end
            if isempty(w) || isempty(h)
                [w, h] = meshgrid(1:obj.Size(2), 1:obj.Size(1));
            end

            %
            h_rel = h-obj.MidPoint(1);
            w_rel = w-obj.MidPoint(2);
            R_pix = sqrt(h_rel.^2 + w_rel.^2); % each point's radial excentricity on the sensor (in pixels)
            R_mm  = R_pix / obj.PixPerMM;      % each point's radial excentricity on the sensor (in mm)
            gamma = atan2d(-h_rel, w_rel) - rotAroundOptAx; % angle around the optical axis

            theta_deg = obj.r2theta(R_mm);           % angle to the optical axis

            r_yz = sind(theta_deg);
            
            X = cosd(theta_deg);
            Y = - r_yz .* cosd(gamma); % This minus makes sure that low image indices are mapped high on the y-axis
            Z = r_yz .* sind(gamma); % No minus makes sure that low image indices are mapped onto high-elevation points

            X(~isreal(X)) = NaN; % set to NaN some points far out of the image circle
            X = real(X);
            Y(~isreal(Y)) = NaN; % set to NaN some points far out of the image circle
            Y = real(Y);
            Z(~isreal(Z)) = NaN; % set to NaN some points far out of the image circle
            Z = real(Z);
            [X, Y, Z] = elf_support_rot3D(X, Y, Z, -optAx(2), 'y');
            [X, Y, Z] = elf_support_rot3D(X, Y, Z, optAx(1), 'z');
        end

        function [w, h] = cart2pix(obj, X, Y, Z, optAx, rotAroundOptAx, roundIt)
            % CART2PIX translates X/Y/Z positions into w/h pixel positions in the image
            %
            % [w, h] = obj.cart2pix(obj, X, Y, Z, [optAx, rotAroundOptAx, roundIt])

            arguments
                obj (1,1) Projector
                X double
                Y double
                Z double
                optAx = ViewDir.H
                rotAroundOptAx (1,1) double = 0
                roundIt (1,1) logical = true
            end

            if isempty(optAx), optAx = ViewDir.H; end
            if isa(optAx, "ViewDir"), optAx = optAx.AzEl; end

            %
            [X, Y, Z] = elf_support_rot3D(X, Y, Z, -optAx(1), 'z');
            [X, Y, Z] = elf_support_rot3D(X, Y, Z, optAx(2), 'y');
            theta_deg = acosd(X);                       % theta is the angle between a viewing direction and the X-axis (X is equal to the scalar dot product of that direction and the X-axis)
            gamma     = atan2d(Z, -Y) + rotAroundOptAx; % gamma is the angle between the Y/Z projection of a viewing direction and the Y axis; 
            R_mm      = obj.theta2r(theta_deg);
            R_pix     = R_mm * obj.PixPerMM;
            w         = R_pix .*  cosd(gamma) + obj.MidPoint(2); % along w; this is 0 + mid for azimuth 0
            h         = R_pix .* -sind(gamma) + obj.MidPoint(1); % along h; this is 0 + mid for elevation 0, and -1 + mid for elevation 90; 
                                                                 % the -sin makes sure that high elevation values are mapped onto a low image index
            if roundIt
                w = round(w);
                h = round(h);
            end
        end

        function [azi, ele] = pix2rect(obj, w, h, optAx, rotAroundOptAx)
            % PIX2RECT translates w/h pixel positions in the fisheye image into azimuth/elevation
            %
            % [azi, ele] = obj.pix2rect(obj, [w, h, optAx, rotAroundOptAx])

            arguments
                obj (1,1) Projector
                w double = []
                h double = []
                optAx = ViewDir.H
                rotAroundOptAx (1,1) double = 0
            end

            if isempty(optAx), optAx = ViewDir.H; end
            if isa(optAx, "ViewDir"), optAx = optAx.AzEl; end
            
            [X, Y, Z]           = obj.pix2cart(w, h, optAx, rotAroundOptAx);
            [azi_rad, ele_rad]  = cart2sph(X, Y, Z);
            azi                 = rad2deg(azi_rad);
            ele                 = rad2deg(ele_rad);
        end

        function [w, h] = rect2pix(obj, azi, ele, optAx, rotAroundOptAx, roundIt)
            % RECT2PIX translates azimuth/elevation into w/h fisheye pixel positions
            %
            % [w, h] = rect2pix(obj, [azi, ele, optAx, rotAroundOptAx, roundIt])

            arguments
                obj (1,1) Projector
                azi double = []
                ele double = []
                optAx = ViewDir.H
                rotAroundOptAx (1,1) double = 0
                roundIt (1,1) logical = true
            end

            if isempty(azi) || isempty(ele)
                [azi, ele] = meshgrid(obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3), obj.ErEle(1):obj.ErEle(2):obj.ErEle(3));
            end

            [X, Y, Z] = sph2cart(deg2rad(azi), deg2rad(ele), 1);
            [w, h]    = obj.cart2pix(X, Y, Z, optAx, rotAroundOptAx, roundIt);
        end

        function [w2, h2] = pix2pix(obj, targetProjector, w, h, rotAroundOptAx, roundIt)
            % PIX2PIX translates w/h pixel positions from one fisheye projection to another
            
            arguments
                obj (1,1) Projector
                targetProjector (1,1) Projector
                w double = []
                h double = []
                rotAroundOptAx (1,1) double = 0
                roundIt (1,1) logical = true
            end
            
            [X, Y, Z]    = obj.pix2cart(w, h, [0,0], 0);
            [w2, h2]     = targetProjector.cart2pix(X, Y, Z, [0,0], rotAroundOptAx, roundIt);
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% IMAGE PROJECTION FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % These functions reproject images between various fisheye/equirectangular projections
    % 
    % Efficient nearest-neighbour-interpolation functions:
    %   (These functions return a projection index vector that can then be used with Projector.apply to reproject any number of images.
    %   The costly part of the calculation therefore only needs to be done once.)
    %   CALCULATEPROJECTION
    %   FISHEYETOFISHEYEPROJECTION
    %   CROPTOIMAGECIRCLE
    %   CALCULATEBACKPROJECTION
    %
    % More accurate interpolation functions:
    %   (These functions use griddata to perform linear/cubic interpolation during reprojection. This can not be done with an index vector, 
    %   so the costly part of the calculation has to be recone for each image.)
    %   INTERPOLATEDPROJECTION
    %   INTERPOLATEDBACKPROJECTION

    methods
        function grids = getProjectionInfo(obj, rotation, viewingDirection)
            % GETPROJECTIONINFO creates the grids for plotting on top of the fisheye and equirectangular image
            %
            % Inputs:
            %  viewingDirection - ViewDir object (from para.ana.imageDirection)
            %
            % Outputs:
            %   grids     - projection grids structure. These can be used in plotting.
            
            if nargin<3 || isempty(viewingDirection), viewingDirection = ViewDir.H; end
            if nargin<2 || isempty(rotation), rotation = 0; end
            grids.azi = obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3);
            grids.ele = obj.ErEle(1):obj.ErEle(2):obj.ErEle(3);

            Logger.log(LogLevel.INFO, '\tCalculating projection grids...\n');

            %% parameters
            gridres1 = 10;  % resolution of the displayed grid between lines
            gridres2 = 1;   % resolution of the displayed grid along lines

            %% Calculate grids for plotting
            
            % a) grid for original projection
            switch viewingDirection
                case {ViewDir.H, ViewDir.W, ViewDir.E, ViewDir.S, ViewDir.N, ViewDir.SE, ViewDir.SW, ViewDir.NE, ViewDir.NW}
                    [gazi1, gele1] = meshgrid(-90:gridres1:90, -90:gridres2:90);
                    [gazi2, gele2] = meshgrid(-90:gridres2:90, -90:gridres1:90);
                    rotation = [rotation 0];

                case {ViewDir.U, ViewDir.D}
                    [gazi1, gele1] = meshgrid(-180:gridres1:179.9, 0:gridres2:90);
                    [gazi2, gele2] = meshgrid(-180:gridres2:180, 0:gridres1:90);
                    rotation = [rotation 90];

                otherwise
                        error("Unknown value for ANALYSIS_IMAGE_DIRECTION")
            end
           
            gazi2                = gazi2';
            gele2                = gele2';

            %  Link all grid lines into a single NaN clipped vector
            r                    = size(gazi1, 1);
            gazi1(r+1, :)        = NaN;
            gele1(r+1, :)        = NaN;
            r                    = size(gazi2, 1);
            gazi2(r+1, :)        = NaN;
            gele2(r+1, :)        = NaN;
            gazi                 = [gazi1(:); gazi2(:)];
            gele                 = [gele1(:); gele2(:)];

            [grids.fisheye.x, grids.fisheye.y] = obj.rect2pix(gazi, gele, rotation);

            % b) grid for projected image (assumes that grid points are included in image grid)
            [~, grids.rect.x] = ismember(gazi, grids.azi);
            [~, grids.rect.y] = ismember(gele, grids.ele);
            grids.rect.x(grids.rect.x==0) = NaN;    % 0 indicates the element was not found
            grids.rect.y(grids.rect.y==0) = NaN;

            Logger.log(LogLevel.INFO, '\bdone.\n')
        end

        function projection_ind = calculateProjection(obj, rotation)
            % CALCULATEPROJECTION creates a projection index vector to transform a fisheye image into an equirectangular (azimuth/elevation) grid
            % using nearest-neighbour interpolation
            %
            % Outputs:
            % projection_ind  - projections index matrix. The projected image can be calculated as im_proj = im(projection_ind)

            if nargin<2 || isempty(rotation), rotation = 0; end
            azi = obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3);
            ele = obj.ErEle(1):obj.ErEle(2):obj.ErEle(3);

            Logger.log(LogLevel.INFO, '\tCalculating projection constants...\n');
            [azi_grid, ele_grid] = meshgrid(azi, ele);   % grid of desired angles
            [w_im, h_im]         = obj.rect2pix(azi_grid, ele_grid, rotation);
            projection_ind       = obj.sub2ind(obj.Size, w_im, h_im);
            Logger.log(LogLevel.INFO, '\bdone.\n');
        end

        function [projection_ind, newProjector] = fisheye2fisheyeProjection(obj, projectionType_new, imSize_new, rotAroundOptAx)
            % FISHEYE2FISHEYEPROJECTION calculates a projection index to warp an image into a different fisheye projection
            % It is also possible to retain the same projection but resize the image.
            % This function uses a simple nearest-neighbour strategy; there is no interpolation.
            % Also creates a Projector object for the new image projection.

            if nargin<4 || isempty(rotAroundOptAx), rotAroundOptAx=0; end

            newProjector = Projector(imSize_new, projectionType_new);

            [w_grid, h_grid]   = meshgrid(1:imSize_new(2), 1:imSize_new(1));          % grid of desired output image coordinates
            [w2_grid, h2_grid] = newProjector.pix2pix(obj, w_grid, h_grid, rotAroundOptAx);
            sel                = w2_grid>obj.Size(2) | w2_grid<1 | h2_grid>obj.Size(1) | h2_grid<1;
            w2_grid(sel)       = NaN; 
            h2_grid(sel)       = NaN;
            projection_ind     = obj.sub2ind(obj.Size, w2_grid, h2_grid);
        end

        function projection_ind = array2image(obj, prArray, optAx)
            % ARRAY2IMAGE calculates a projection index to project activations of a photoreceptor
            % photoreceptor array onto a fisheye image.
            %
            % Inputs: 
            %   prArray - Nx3 array of XYZ photoreceptor angles
            %
            % Outputs:
            %   projection_ind  - projections index matrix. 
            % 
            % The projected image can be calculated as 
            % im_proj = Projector.apply(projection_ind, im, proj.Size)

            % Check if this already exists in the buffer
            projection_ind = Buffer.retrieve("Array2ImageProjection", {obj, prArray, optAx});
            if ~isempty(projection_ind)
                    Logger.log(LogLevel.INFO, '\tProjection found in buffer...loaded.\n');
                return
            end

            % Calculate projection
                Logger.log(LogLevel.INFO, '\tCalculating projection of photoreceptor array onto fisheye image...\n');
            [w_grid, h_grid] = meshgrid(1:obj.Size(2), 1:obj.Size(1)); % grid of desired output image coordinates
            [x, y, z] = obj.pix2cart(w_grid(:), h_grid(:), optAx);
            xyz = [x(:) y(:) z(:)]';

            prArray3xN = prArray';  % make into 3xN
            projection_ind = nan(size(x));
            nRecs = size(prArray, 1);
            
            wbh = waitbar(0, sprintf('Projecting receptor array onto image'), "Name", "Calculating projection"); drawnow
            updateFreq = round(length(x)/100);  % update waitbar every 
            try
                for i = 1:length(x)
                    exc = acosd(dot(prArray3xN, repmat(xyz(:, i), [1, nRecs])));
                    [~, projection_ind(i)] = min(exc);
                    if mod(i, updateFreq)==0
                        waitbar(i/length(x), wbh);
                    end
                end
            catch me
                try close(wbh); end
                rethrow(me)
            end
            try close(wbh); end
            projection_ind = obj.sub2ind2(size(prArray), projection_ind);
            Logger.log(LogLevel.INFO, '\bdone.\n');

            % Store everything in the buffer
            Buffer.store("Array2ImageProjection", {obj, prArray, optAx}, projection_ind);
                Logger.log(LogLevel.INFO, '\tProjection stored in buffer.\n');
        end

        function [projection_ind, newProjector] = crop2ImageCircle(obj, maxRadius_deg)
            % CROP2IMAGECIRCLE calculates a projection index to crop an image tightly around an image circle with a given radius. Even if the original
            % image is off-centre, the new image will be centred.
            % Also creates a Projector object for the new image projection.

            newProjector = Projector.fromImageCircle(obj, maxRadius_deg);

            [w_grid, h_grid]   = meshgrid(1:newProjector.Size(2), 1:newProjector.Size(1)); % grid of desired output image coordinates
            [w2_grid, h2_grid] = newProjector.pix2pix(obj, w_grid, h_grid);
            sel                = w2_grid>obj.Size(2) | w2_grid<1 | h2_grid>obj.Size(1) | h2_grid<1;
            w2_grid(sel)       = NaN; 
            h2_grid(sel)       = NaN;
            projection_ind     = obj.sub2ind(obj.Size, w2_grid, h2_grid);
        end

        function projection_ind = calculateBackProjection(obj, rotation)
            % CALCULATEBACKPROJECTION creates a projection index vector to transform an equirectangular image back to a fisheye image
            %
            % Outputs:
            % projection_ind  - projections index matrix. The projected image can be calculated as im_proj = im(projection_ind)

            if nargin<2 || isempty(rotation), rotation = 0; end
            azi = obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3);
            ele = obj.ErEle(1):obj.ErEle(2):obj.ErEle(3);
            
            %% Calculate main projections   
            Logger.log(LogLevel.INFO, '\tCalculating projection constants...\n'); 
            [w_grid, h_grid]         = meshgrid(1:obj.Size(2), 1:obj.Size(1)); % grid of desired output image coordinates
            [target_azi, target_ele] = obj.pix2rect(w_grid, h_grid, rotation);
            % calculate azi/ele index vectors
            azi_ind                  = (target_azi - azi(1)) / obj.ErAzi(2) + 1;
            ele_ind                  = (target_ele - ele(1)) / obj.ErEle(2) + 1;
            % remove out-of-bounds azi and ele pairs
            sel                      = target_azi>max(azi) | target_azi<min(azi) | target_ele>max(ele) | target_ele<min(ele);
            azi_ind(sel)             = NaN; 
            ele_ind(sel)             = NaN;
            % and create linear index vector
            projection_ind           = obj.sub2ind([length(ele) length(azi) obj.Size(3)], azi_ind, ele_ind);
            Logger.log(LogLevel.INFO, '\bdone.\n');
        end

        function im_rect = interpolatedProjection(obj, im, rotation, method)
            % INTERPOLATEDPROJECTION takes a fisheye image and projects it to an equirectangular image using interpolation.
            %
            % Inputs:
            % im       - MxNxC double, the fisheye image to be transformed
            % rotation - Angle (in degrees) by which the image should be rotated before processing (Use 90 or -90 for portrait images)
            % method   - method to use in griddata ("linear"/"nearest"/"natural"/"cubic"/"v4")
            %            to use old "nearestneighbour" method, use
            %            obj.calculateBackProjection and Projector.apply
            %
            % Outputs:
            % im_rect  - Output equirectangular image

            if nargin < 4 || isempty(method), method = 'linear'; end
            if nargin < 3 || isempty(rotation), rotation = 0; end
            azi = obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3);
            ele = obj.ErEle(1):obj.ErEle(2):obj.ErEle(3);
            [azi_grid, ele_grid]     = meshgrid(azi, ele);  % grid of desired angles

            [w_grid, h_grid]         = meshgrid(1:obj.Size(2), 1:obj.Size(1)); % grid of desired output image coordinates
            [target_azi, target_ele] = obj.pix2rect(w_grid, h_grid, rotation);
            % remove out-of-bounds azi and ele pairs
            sel                      = target_azi>max(azi) | target_azi<min(azi) | target_ele>max(ele) | target_ele<min(ele) | isnan(target_azi) | isnan(target_ele);

            im_rect              = zeros(obj.RectSize); % pre-allocate
            for ch = 1:obj.Size(3) % for each channel
                thisch               = im(:, :, ch);
                warning('off', 'MATLAB:griddata:DuplicateDataPoints');
                im_rect(:, :, ch) = griddata(target_azi(~sel), target_ele(~sel), thisch(~sel), azi_grid, ele_grid, method); %#ok<GRIDD>
                warning('on', 'MATLAB:griddata:DuplicateDataPoints');

                %% Alternative: scatteredInterpolant version, which is a LOT slower (~10x), but gives the same results
                %             F = scatteredInterpolant(y_im(:), x_im(:), thisch(:));
                %             im_fisheye(:, :, ch) = F(y_grid, x_grid);
            end
        end

        function im_fisheye = interpolatedBackProjection(obj, im, rotation, method)
            % INTERPOLATEDBACKPROJECTION takes an equirectangular image and projects it back to a fisheye image using interpolation.
            %
            % Inputs:
            % im         - MxNxC double, the equirectangular image to be transformed
            % rotation   - Angle (in degrees) by which the image should be rotated before processing (Use 90 or -90 for portrait images)
            % method     - method to use in griddata ("linear"/"nearest"/"natural"/"cubic"/"v4")
            %              to use old "nearestneighbour" method, use
            %              obj.calculateBackProjection and Projector.apply
            %
            % Outputs:
            % im_fisheye - Output fisheye image

            if nargin < 4 || isempty(method), method = 'linear'; end
            if nargin < 3 || isempty(rotation), rotation = 0; end
            azi = obj.ErAzi(1):obj.ErAzi(2):obj.ErAzi(3);
            ele = obj.ErEle(1):obj.ErEle(2):obj.ErEle(3);

            [azi_grid, ele_grid]    = meshgrid(azi, ele);  % grid of desired angles
            [w_im, h_im]            = obj.rect2pix(azi_grid, ele_grid, -rotation);
            [w_grid, h_grid]        = meshgrid(1:obj.Size(2), 1:obj.Size(1));   % grid of desired output pixels

            im_fisheye              = zeros(obj.Size); % pre-allocate
            for ch = 1:obj.Size(3) % for each channel
                thisch               = im(:, :, ch);
                warning('off', 'MATLAB:griddata:DuplicateDataPoints');
                im_fisheye(:, :, ch) = griddata(h_im(:), w_im(:), thisch(:), h_grid, w_grid, method); %#ok<GRIDD>
                warning('on', 'MATLAB:griddata:DuplicateDataPoints');

                %% Alternative: scatteredInterpolant version, which is a LOT slower (~10x), but gives the same results
                %             F = scatteredInterpolant(y_im(:), x_im(:), thisch(:));
                %             im_fisheye(:, :, ch) = F(y_grid, x_grid);
            end
            im_fisheye = obj.blackout(im_fisheye); % set points beyond 90 degrees to 0
        end

        function im = blackout(obj, im, excLimit, zeroValue)
            % BLACKOUT takes a fisheye image and sets all image point beyond a certain excentricity (default 90 degrees) to 0 or NaN
            % Inputs:
            % im        - MxNxC double, the fisheye image to be transformed
            % excLimit  - default: 90; excentricity limit in degrees; any value with a greater excentricity (angle to the optiocal axis) 
            %             than this will be set to zeroValue
            % zeroValue - default: 0; zero value: any value with a greater excentricity than excLimit this will be set to this value
            %
            % Outputs:
            % im        - processed image

            if nargin<4 || isempty(zeroValue), zeroValue = 0; end
            if nargin<3 || isempty(excLimit), excLimit = 90; end
            
            [w, h]      = meshgrid(1:obj.Size(2), 1:obj.Size(1));
            r           = sqrt((h-obj.MidPoint(1)).^2 + (w-obj.MidPoint(2)).^2);
            R_mm        = r / obj.PixPerMM;
            theta_deg   = obj.r2theta(R_mm);
            sel         = theta_deg>excLimit;
            tempim      = cell(obj.Size(3), 1);
            for i = 1:obj.Size(3)
                tempim{i} = im(:, :, i); 
                tempim{i}(sel) = zeroValue;
            end
            im = cat(3, tempim{:});
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% STATIC HELPER FUNCTIONS %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Static)
        function d = sphericalDist(X, Y, Z, XYZ2, projType)
            %


            if nargin<7, projType = 'xyz'; end
            if size(XYZ2, 1)~=3 || size(XYZ2, 2)~=1
                error("XYZ2 must be a 3x1 matrix");
            end
            switch projType
                case {'xyz', 'cart'}
                    XYZ1 = [X(:)'; Y(:)'; Z(:)']; % 3xN
                    XYZ2 = repmat(XYZ2(:), [1, size(XYZ1, 2)]);
                    d = reshape(acosd(dot(XYZ1, XYZ2)), size(X)); % angular distance in degrees for every pixel
                otherwise
                    error("Unknown type, or Projector.sphericalDist is not yet implemented for type %s", projType);
            end
        end

        function im = apply(im, proj_ind, imsize)
            % PROJECTOR.APPLY applies a linear index vector ind to a three-dimensional matrix (image).
            % Use this for quick reprojection of images.
            %
            % Inputs:
            % im            - image to which to apply the projection
            % proj_ind      - linear index vector into the first two dimensions of im (obtained from Projector.sub2ind)
            % imsize        - 3x1 double, size of the output image
            %
            % Outputs:
            % im            - the projected image
            %
            % Usage example:
            % proj           = Projector.fromInfoStructs(I_info, projInfo)
            % [w_im, h_im]   = proj.rect2pix(azi, ele);
            % imsize_fisheye = [I_info.Height I_info.Width I_info.SamplesPerPixel];
            % ind            = Projector.sub2ind(imsize_fisheye, w_im, h_im)
            % imsize_rect    = [length(ele) length(azi) I_info.SamplesPerPixel];
            % im             = Projector.apply(im, ind, imsize_rect)

            sel           = isnan(proj_ind); 
            proj_ind(sel) = 1; % NaNs in the projection index indicate invalid points. Remove for now, and set to NaN later
            im_temp       = im(proj_ind); % index image
            im_temp(sel)  = NaN; % now set invalid points to NaN
            im            = reshape(im_temp, imsize); % and reshape back into an image
        end

        function ind = sub2ind(imsize, w_im, h_im)
            % PROJECTOR.SUB2IND turns x/y subscript index vectors into a linear index vector ind for a three-dimensional matrix
            % Use this for quick reprojection of images.++
            %
            % Inputs:
            % imsize            - 3x1 double, size of the image to be sampled
            % w_im, h_im        - image coordinates obtained from Projector.rect2pix
            %
            % Outputs:
            % projection_ind    - projections index matrix. The projected image can be calculated as im_proj = im(projection_ind)
            %
            % Example:
            % proj           = Projector.fromInfoStructs(I_info, projInfo)
            % [w_im, h_im]   = proj.rect2pix(azi, ele);
            % imsize_fisheye = [I_info.Height I_info.Width I_info.SamplesPerPixel];
            % ind            = Projector.sub2ind(imsize_fisheye, w_im, h_im)
            
            %% calculate linear index vector for projection
            ind1      = repmat(round(h_im(:)), imsize(3), 1); % repeat three times to call for each channel
            ind2      = repmat(round(w_im(:)), imsize(3), 1); % repeat three times to call for each channel
            ind3      = reshape(repmat(1:imsize(3), length(w_im(:)), 1), [], 1);
            
            sel       = isnan(ind1) | isnan(ind2);
            ind1(sel) = 1;
            ind2(sel) = 1;
            
            ind       = sub2ind(imsize, ind1, ind2, ind3);  % transform into linear indexes

            ind(sel)  = NaN;
        end

        function ind = sub2ind2(imsize, i_im)
            % PROJECTOR.SUB2IND2 is the 2D version of PROJECTOR.SUB2IND and can be used on a whole image stack
            % i_im              - 1st image coordinate (e.g. list-index)
            
            %% calculate linear index vector for projection
            ind1    = repmat(round(i_im(:)), imsize(2), 1); % repeat three times to call for each channel
            ind2    = reshape(repmat(1:imsize(2), length(i_im(:)), 1), [], 1);
            
            ind1(ind1>imsize(1)) = NaN;
            ind2(ind2>imsize(2)) = NaN;
            ind1(ind1<1) = NaN;
            ind2(ind2<1) = NaN;
            
            ind     = sub2ind(imsize, ind1, ind2);  % transform into linear indexes
        end

        function ind = sub2ind4(imsize, w_im, h_im, n_im)
            % PROJECTOR.SUB2IND4 is the 4D version of PROJECTOR.SUB2IND and can be used on a whole image stack
            % n_im              - 4th image coordinate obtained from stitch_5dirs
            
            %% calculate linear index vector for projection
            ind1    = repmat(round(h_im(:)), imsize(3), 1); % repeat three times to call for each channel
            ind2    = repmat(round(w_im(:)), imsize(3), 1); % repeat three times to call for each channel
            ind3    = reshape(repmat(1:imsize(3), length(w_im(:)), 1), [], 1);
            ind4    = repmat(n_im(:), imsize(3), 1);
            
            ind1(ind1>imsize(1)) = NaN;
            ind2(ind2>imsize(2)) = NaN;
            ind1(ind1<1) = NaN;
            ind2(ind2<1) = NaN;
            
            ind     = sub2ind(imsize, ind1, ind2, ind3, ind4);  % transform into linear indexes
        end
    end
end