function [para, status, gui] = elf_startup(modules, cbhandle, rootfolder, verbose, useoldfolder)

%% defaults
if nargin < 5 || isempty(useoldfolder), useoldfolder = true; end
if nargin < 4 || isempty(verbose), verbose = true; end
if nargin < 3 || isempty(rootfolder), rootfolder = ''; end

%% get basic parameters
if useoldfolder
    para = elf_para(modules, rootfolder, '', '', true); % without arguments, just returns basic parameters (call again later with rootfolder or dataset)
else
    para = elf_para(modules, NaN, '', '', true); % without arguments, just returns basic parameters (call again later with rootfolder or dataset)
end

%% collect and check all datasets parameters
[status, para, datasets, exts] = elf_checkdata(para, verbose);

%% build GUI
if para.modules{1} ~= "core"
    figName = upper(para.modules{1}) + "-ELF";
else
    figName = "ELF";
end
gui = elf_maingui(status, para, datasets, exts, cbhandle, figName);

%% insert images
for i = 1:size(status, 1)
    para2 = elf_para(modules, para.paths.root, datasets{i});
    if status(i, 3)
        fname   = para2.paths.fname_meanimg_jpg;
        info    = [];
        corr    = false;
    else
        % if no summary exists, show the first scene, or the second raw image (this is usually the first mid-exposure)
        if isnan(exts{i}) % this happens when there are only raw files in the folder
            mask = '*.*';
        else
            mask = ['*' exts{i}];
        end
        scenepath = fullfile(para2.paths.datapath, para2.paths.scenefolder);
        if isfolder(scenepath) && ~isempty(elf_io_dir(fullfile(scenepath, '*.tif')))
            allims = elf_io_dir(fullfile(scenepath, '*.tif'));
            fname  = fullfile(allims(1).folder, allims(1).name);
        else
            allims = elf_io_dir(fullfile(para2.paths.datapath, mask));
            allims([allims.isdir]) = [];
            imind  = min([2, length(allims)]);
            fname  = fullfile(allims(imind).folder, allims(imind).name);
        end

        info = elf_info_load(fname);
        if strcmp(exts{i}, '.dng')
            corr = "bright"; % if these are dng images, perform colour and gamma correction
        else
            corr = false;
        end
    end
    [I, compressed]  = elf_io_imread(fname, true); % pass over a CompressedDNG error here
    switch compressed
        case ''
            % all good
        case 'ELF:io:dngCompressed'
            status(i, 1) = 2;
        otherwise
            status(i, 1) = 4;
    end
    scale   = para.gui.smallsize/size(I, 2);
    I       = imresize(I, scale);
    elf_plot_image(I, info, gui.p(i).ah, '', corr);
    drawnow;
end

elf_maingui_visibility(gui, status);
