function elf_mainX_explore(dataSet, modules, ~)
    % ELF_MAINX_EXPLORE shows a montage of all scenes
    
    % Loads files: *.tif files in scenes folder
    
    if nargin < 2 , modules = {}; end
    if nargin < 1 || isempty(dataSet), error('You have to provide a valid dataset name'); end 
    
    %% Set up paths and file names; read info, infosum and para
    elf_paths;
    para            = elf_para(modules, '', dataSet);
    para            = elf_para_update(para);                      % Combine old parameter file with potentially changed information in current config
    infoSum         = elf_io_readwrite(para, 'loadinfosum');      % loads the old infosum file (which contains projection information, and linims)
    allFiles  = elf_io_dir(fullfile(para.paths.datapath, para.paths.scenefolder, '*.tif'));
    fNames_im = {allFiles.name}; % collect scene names

                    Logger.log(LogLevel.INFO, '\b\b\b\b\b\b\b\b\b\b\b\b\b\n');
                    Logger.log(LogLevel.INFO, '----- ELF Step X: Explore -----\n');
                    Logger.log(LogLevel.INFO, '      Processing environment %s\n', para.paths.dataset);
    
    %% calculate thumbs
    thumbs = zeros(100, 100, infoSum.SamplesPerPixel, length(allFiles), infoSum.class{1});      % pre-allocate for thumbnails of all processed images
    for imnr = 1:length(allFiles)
        thisIm = elf_io_readwrite(para, 'loadHDR_tif', fNames_im{imnr}); % output is uint16        
        thumbs(:, :, :, imnr) = imresize(thisIm, [100 100]);
    end
    
    %% Plot thumbs
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

















