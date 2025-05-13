function elf_mainX_exploreDiag(dataSet, modules)
% ELF_MAIN4_DISPLAY simply displays the intensity mean and mean image for a dataset
%
% elf_main4_display(dataSet, imgFormat)

if nargin < 2 , modules = {}; end
    if nargin < 1 || isempty(dataSet), error('You have to provide a valid dataset name'); end 
    
    %% Set up paths and file names; read info, infosum and para
    elf_paths;
    para            = elf_para(modules, '', dataSet);
    para            = elf_para_update(para);      % Combine old parameter file with potentially changed information in current config
    infoSum         = para.fh.loadInfoSum();      % loads the old infosum file (which contains projection information, and linims)
    allFiles  = elf_io_dir(fullfile(para.fh.Paths.datapath, para.fh.Paths.diagfolder, '*.tif'));
    fNames_im = {allFiles.name}; % collect scene names

                    Logger.log(LogLevel.INFO, '\n----- ELF Step X: Show Diagnostics -----\n');
                    Logger.log(LogLevel.INFO, '      Processing environment %s\n', para.fh.Paths.dataset);

    %% calculate thumbs
    thumbs = zeros(100, 100, infoSum.SamplesPerPixel, length(allFiles), infoSum.class{1});      % pre-allocate for thumbnails of all processed images
    for imnr = 1:length(allFiles)
        thisIm = para.fh.loadSceneDiag_tif(fNames_im{imnr}); % output is uint8
        thumbs(:, :, :, imnr) = imresize(thisIm, [100 100]);
    end
    
    %% Plot thumbs
    fh2 = figure(3);
    set(fh2, 'Name', 'Thumbnails (click to enlarge)');
    if size(thumbs, 4)==1
        hi2 = montage({thumbs}, 'thumbnailsize', [100 100], BackgroundColor="white", BorderSize=[1 1]);  % if thumbs is just a single MxNx3 image, it would be interpreted as 3 grayscale-images
    else
        hi2 = montage(double(thumbs), 'thumbnailsize', [100 100], BackgroundColor="white", BorderSize=[1 1]);
    end
    res.fnames_im = fNames_im;
    res.infosum = infoSum;
    res.para = para;
    set(hi2, 'ButtonDownFcn', @(x,y) elf_callbacks_montage(x, y, 'diag'), 'UserData', res);
end