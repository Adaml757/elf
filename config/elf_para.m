function para = elf_para(desiredModules, rootdir, dataset, imgformat, verbose)
% ELF_PARA defines some of the basic anlysis parameters for ELF
% 
%
% if called without dataset, just collects basic info
% rootdir = NaN or rootdir = 'reset' means reset all local folders; rootdir = 'noenv' means just return the default parameters, don't read .env file
% empty rootdir means load all saved folders
% rootdir = 'prompt' means prompt for root dir but use saved output folders
% desiredModules can be the name of a single module (e.g. "filter") or a cell array of module names

%% defaults
if nargin < 5, verbose = false; end
if nargin < 4, imgformat = ""; end
if nargin < 3, dataset = ''; end
if nargin < 2, rootdir = ''; end
if nargin < 1, desiredModules = {}; end
if ~iscell(desiredModules), desiredModules = {desiredModules}; end

%% find root folder
mayusegpu = false; % this flag can be used to manually (de-)activate use of GPU computing
[para.syst, para.thisv, para.usegpu] = elf_versioncheck(verbose, mayusegpu); % Check operating system and Matlab version

if ~isa(rootdir, "string") && any(isnan(rootdir)) || strcmp(rootdir, 'reset')
    % reset and prompt for all local input/output folders
    paths.root             = elf_io_localpaths('loadroot', true);
    paths.outputfolder     = elf_io_localpaths('loadoutput', true);
    paths.outputfolder_pub = elf_io_localpaths('loadoutput_pub', true);
elseif any(isempty(rootdir)) || strcmp(rootdir, 'noenv')
    % use saved input/output folders
    paths.root             = elf_io_localpaths('loadroot', false);
    paths.outputfolder     = elf_io_localpaths('loadoutput', false);
    paths.outputfolder_pub = elf_io_localpaths('loadoutput_pub', false);
elseif strcmp(rootdir, 'prompt') || ~exist(rootdir, 'file')
    % prompt for data folder, but use saved output folders
    paths.root             = elf_io_localpaths('loadroot', true);
    paths.outputfolder     = elf_io_localpaths('loadoutput', false);
    paths.outputfolder_pub = elf_io_localpaths('loadoutput_pub', false);
else
    % if a directory was specified, and it exists, use it and save it as the new default
    paths.root = rootdir;
    elf_io_localpaths('saveroot', 0, rootdir);
    paths.outputfolder     = elf_io_localpaths('loadoutput');
    paths.outputfolder_pub = elf_io_localpaths('loadoutput_pub');
end

%% define further folder structure
paths.matfolder        = "mat";            % subfolder of data folder into which to save the .mat descriptor files (and individual .pdf files, if activated) 
paths.filtfolder       = "filt";           % subfolder of data folder into which to save the filtered images
paths.polarfolder      = "polar";           % subfolder of data folder into which to save the filtered images
paths.scenefolder      = "scenes";         % subfolder of data folder into which to save the scene images
paths.diagfolder       = "diag";         % subfolder of data folder into which to save the diagnostic images
paths.calibfolder      = fullfile(fileparts(mfilename('fullpath')), '..', 'calibration');

%% if this is called for a specific dataset, store that information
if ~isempty(dataset)
    paths.dataset      = dataset;
    paths.imgformat    = imgformat;
    paths.datapath     = fullfile(paths.root, paths.dataset);
    para.fh            = FileHandler(paths);
    para.fh.init();
end

%% load .env files
if strcmp(rootdir, 'noenv')
    return
end

%% Check whether all modules and dependencies are installed, and load their .env files
[para.modules, para.ana, para.plot] = elf_modules_addWithDependencies(desiredModules);

%% projection constants (don't change)
para.azi                    = [para.ana.targetAziRange(1), .1/para.ana.resolutionBooster, para.ana.targetAziRange(2)];          % regular elevation sampling for equirectangular projection
para.ele                    = [para.ana.targetEleRange(1), .1/para.ana.resolutionBooster, para.ana.targetEleRange(2)];          % regular azimuth sampling for equirectangular projection
para.ele2                   = [para.ana.targetEleRange(2), -.1/para.ana.resolutionBooster, para.ana.targetEleRange(1)];

%% main ELF gui parameters
%% TODO: Could be moved to core .env file
para.gui.pnum_cols = 8; % 8 tiles horizontally
para.gui.pnum_rows = 6; % 6 tiles vertically
para.gui.smallsize = 200; % size of small preview images in ELF gui

%% spatial analysis constants
%% TODO: Move to .env when spatial module is overhauled
para.ana.spatialbins        = [-90 -10 10 90];%[-90 -50 -10 10 50 90]; % define the boundaries of bins for spatial/contrast analysis
para.ana.spatialmeantype    = 'rms';    % can be 'mean'/'rms'/'perc'; if this is changed, step 3 and 4 have to be recalculated
para.ana.spatialmeanthr     = 0;        % contrast threshold in percent; only contrasts >= this value will be included in the mean

