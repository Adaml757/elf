function [para, infoSum] = core_perEnvironment(para, infoSum, verbose)
    %CORE_PERENVIRONMENT calculates the mean image and intensity descriptors for an ELF environment
    %   The mean image is calculated as the mean of all normalised HDR scenes. 
    %      Scenes are normalised in elf_main1 using the correctdng "bright" method, 
    %      which sets the mean luminance to 1/4 of maximum.
    %   Results are saved as TIF/JPG (mean image), XLSX file and PDF/JPG (int)
    %
    % Inputs:
    %   para     - ELF parameter structure
    %   infoSum  - exif structure used for plotting, Projector objects, and gamma-correction
    %   verbose  - whether to plot filtered images along the way
    %
    % Outputs:
    %   para     - ELF parameter structure 
    %   infoSum  - exif structure

    allFiles  = elf_io_dir(fullfile(para.paths.datapath, para.paths.scenefolder, '*.tif'));
    fNames_im = {allFiles.name}; % collect scene names

    if para.ana.calculateMeanImage
                    Logger.log(LogLevel.INFO, '\n----- ELF Step 2: Mean Image -----\n');
                    Logger.log(LogLevel.INFO, '      Processing environment %s\n', para.paths.dataset);

        %% Calculate mean image and thumbs
        if verbose
            fh = figure(22); clf; 
            hp = uipanel('Parent', fh); 
            hi = [];
            thumbs = zeros(100, 100, infoSum.SamplesPerPixel, length(allFiles), infoSum.class{1});      % pre-allocate for thumbnails of all processed images
        end
        
        for imnr = 1:length(allFiles)
            thisIm = elf_io_readwrite(para, 'loadHDR_tif', fNames_im{imnr}); % output is uint16
            if imnr==1
                sumImage = double(thisIm);
            else
                sumImage = sumImage + double(thisIm);                             % add this image to the sum image
            end
        
            if verbose
                % calculate thumbnails of each image to display in a montage later
                thumbs(:, :, :, imnr) = imresize(thisIm, [100 100]);
        
                if isempty(hi) % first execution
                    hi = elf_plot_image(thisIm, [], hp);
                else 
                    set(hi, 'CData', thisIm);
                end
                set(fh, 'name', sprintf('Image %d of %d', imnr, length(allFiles))); 
                drawnow;
            end
        end
        if verbose, close(fh); end
        meanImage = sumImage/length(allFiles);
        
        %% Plot mean image and thumbs
        % a) Display montage of thumbs
        if verbose
            fh2 = figure(2);
            set(fh2, 'Name', 'Thumbnails (click to enlarge)');
            if size(thumbs, 4)==1
                hi2 = montage({thumbs}, 'thumbnailsize', [100 100]);  % if thumbs is just a single MxNx3 image, it would be interpreted as 3 grayscale-images
            else
                hi2 = montage(thumbs, 'thumbnailsize', [100 100]);
            end
            res.fnames_im = fNames_im;
            res.infosum = infoSum;
            res.para = para;
            res.data = elf_io_readwrite(para, 'loadres', fNames_im);    
            set(hi2, 'ButtonDownFcn', @elf_callbacks_montage, 'UserData', res);
        end
        
        % b) Display mean image in figure 2
        fh3 = elf_support_formatA4(21, 2);
        set(fh3, 'Name', 'Mean image');
        p3 = uipanel('Parent', fh3);
        elf_plot_image(meanImage, infoSum, p3, 'equirectangular', infoSum.linims);
        
        %% Save output to tif and jpg
        elf_io_readwrite(para, 'savemeanimg_tif', '', uint16(meanImage));
        elf_io_readwrite(para, 'savemeanimg_jpg', '', uint16(meanImage));
    end
    
    if para.ana.calculateInt
                    Logger.log(LogLevel.INFO, '\n----- ELF Step 3: Calculating and plotting intensity summary -----\n');

        %% Calculate mean intensity
        data    = elf_io_readwrite(para, 'loadres', fNames_im);
        intMean = elf_analysis_datasetmean(data, 1:length(data), 1, para.plot.datasetMeanType); % Calculate descriptor mean for intensities
        elf_io_readwrite(para, 'savemeanres_int', '', intMean); % write data mean
        
        %% Write stats into CSV file
        elf_analysis_writestats(intMean, para.paths.fname_stats);
                
        %% Plot results
        h       = elf_plot_intSummary(intMean, uint16(meanImage), infoSum, para.plot, para.paths.dataset, length(fNames_im));
        
        %% Save output to pdf and tif
        elf_io_readwrite(para, 'savemeanivep_jpg', '', h.fh);
        elf_io_readwrite(para, 'savemeanivep_pdf', '', h.fh);
    end
end

