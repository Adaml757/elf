function [im_HDR, im_diag] = elf_hdr_calcHDR(im_cal, conf, hdrMethod, rawWhiteLevels, lowerLimit)
% ELF_HDR_CALCHDR calculates an HDR image from a stack of calibrated images.
%
%   im_HDR = elf_hdr_calcHDR(im_cal, conf, hdrMethod, confsat)
%
% Inputs:
%   im_cal    - N x M x C x I double, calibrated image stack
%   conf      - N x M x C x I double, raw (dark-corrected) image stack, used for confidence/saturation calculation
%   hdrMethod - 'overwrite'/'overwrite2'/'validranges'/'allvalid'/'allvalid2'(current default)/'noise', see below for details of methods
%   rawWhiteLevels   - C x I double, the saturation values for each channel/image, obtained from elf_calib_abssens
%
% Outputs:
%   im_HDR   - N x M x C double, calibrated HDR image
%   im_diag  - N x M x 3 logical, diagnostic image with warning flags for saturation (R) / low signal (G) / movement (B)

if nargin<5, lowerLimit = 50; end  % define the lower limit of raw camera counts (after dark correction) which to define as too dark for diag image

N = size(im_cal, 1);
M = size(im_cal, 2);
nChs = size(im_cal, 3);
nIms = size(im_cal, 4);

if nIms == 1
    % if only one exposure was taken, no HDR image needs to be calculated
    im_HDR      = im_cal;

    satlimfull  = repmat(reshape(rawWhiteLevels(:, 1), [1 1 nChs]), N, M);
    diag_sat    = conf>=satlimfull;
    diag_lowsig = conf<=lowerLimit;
    im_diag     = cat(3, any(diag_sat, 3), any(diag_lowsig, 3), false(N, M));
    return;
end

% pre-allocate
im_HDR  = nan(N, M, nChs);
im_diag = false(N, M, 3);

switch hdrMethod
    case 'overwrite'
        %% Starting with the lowest exposure, overwrite all pixels that are not saturated
        im_HDR_cell = cell(nChs, 1);
        diag_sat = cell(nChs, 1);
        diag_lowsig = cell(nChs, 1);

        for ch = 1:nChs
            ul                  = rawWhiteLevels(ch, :);
            ul(1)               = Inf;
            im_HDR_cell{ch}     = nan(N, M); % pre-allocate
            diag_sat{ch}        = nan(N, M); % pre-allocate
            diag_lowsig{ch}     = nan(N, M); % pre-allocate

            for iIm = 1:nIms  % for each image, starting at the darkest image
                thisimch        = im_cal(:, :, ch, iIm); % extract THIS row for THIS channel for THIS image
                thisconf        = conf(:, :, ch, iIm);
                sel             = thisconf<ul(iIm);
                im_HDR_cell{ch}(sel) = thisimch(sel);

                sat = thisconf>=rawWhiteLevels(ch, :);
                diag_sat(sel)  = sat(sel);

                lowsig = thisconf<=lowerLimit;
                diag_lowsig(sel)  = lowsig(sel);
            end
        end

        im_HDR  = cat(3, im_HDR_cell{:});
        im_diag = cat(3, any(diag_sat, 3), any(diag_lowsig, 3), false(N, M));
        
    case 'overwrite2'
        %% same, but more vectorised, so maybe slightly faster
        ul  = rawWhiteLevels;
        ul(:, 1) = Inf;
        
        for iIm = 1:nIms  % for each image, starting at the darkest image
            ulfull                  = repmat(reshape(ul(:, iIm), [1 1 nChs]), N, M);
            thisim                  = im_cal(:, :, :, iIm);
            thisconf                = conf(:, :, :, iIm);
            im_HDR(thisconf<ulfull) = thisim(thisconf<ulfull);
        end

        %% TODO: Calculate im_diag, if this method needs to ever be used

    case 'allvalid'
        %% always use the brightest pixel where NONE of the channels is saturated. 

        for i = 1:N
            for j = 1:M
                % find the highest exposure that has no saturated pixels
                bestind = find(~any(squeeze(conf(i, j, :, :))>=rawWhiteLevels), 1, 'last');
                lowsig  = any(squeeze(conf(i, j, :, :))<=lowerLimit, 1); % for each image, whether this pixel is low-signal
                if ~isempty(bestind)
                    im_HDR(i, j, :) = im_cal(i, j, :, bestind);
                    im_diag(i, j, 1) = false;
                    im_diag(i, j, 2) = lowsig(bestind);
                else
                    % if all are saturated, use the estimate from the darkest image
                    im_HDR(i, j, :) = im_cal(i, j, :, 1);
                    im_diag(i, j, 1) = true;
                    im_diag(i, j, 2) = lowsig(1);
                end
            end
        end

    case 'allvalid2' % (current default in default.env)
        %% same, but  vectorised, so maybe faster
        ul  = rawWhiteLevels; % upper limit = saturation limit (corrected for dark level)
        ul(:, 1) = Inf;
        
        diag_sat = false(N, M, nChs);
        diag_lowsig = false(N, M, nChs);

        for iIm = 1:nIms  % for each image, starting at the darkest image
            ulfull                  = repmat(reshape(ul(:, iIm), [1 1 nChs]), N, M);
            thisim                  = im_cal(:, :, :, iIm);
            thisconf                = conf(:, :, :, iIm);
            sel                     = thisconf<ulfull;
            sel2                    = repmat(all(sel, 3), [1 1 nChs]);
            im_HDR(sel2)            = thisim(sel2);

            satlimfull              = repmat(reshape(rawWhiteLevels(:, iIm), [1 1 nChs]), N, M);
            thissat                 = thisconf>=satlimfull;
            diag_sat(sel2)          = thissat(sel2);

            thislowsig              = thisconf<=lowerLimit;
            diag_lowsig(sel2)       = thislowsig(sel2);

                        
        end
        
        im_diag = cat(3, any(diag_sat, 3), any(diag_lowsig, 3), false(N, M));
        
    case 'noise'
        %% NOISE METHOD: each pixel is the weighted average of the same pixel in different exposures.
        % Weights depend on the inverse of the modelled noise (currently: simply the square root of the raw count).
        % Saturated pixels had their confidence set to NaN in Calibrator.apply.
        fullsat = zeros(size(conf));
        for ch = 1:size(rawWhiteLevels, 1)
            for im = 1:size(rawWhiteLevels, 2)
                fullsat(:, :, ch, im) = rawWhiteLevels(ch, im);
            end
        end
        conf(conf>=fullsat) = 0;
        conf(conf<0) = 0;
        HDRweights  = sqrt(conf);
        im_HDR      = nansum(im_cal .* HDRweights, 4) ./ nansum(HDRweights, 4);

        %% TODO: Calculate im_diag, if this method needs to ever be used
        
    otherwise
        error('Internal error: Unknown HDR method: %s', hdrMethod);
end



