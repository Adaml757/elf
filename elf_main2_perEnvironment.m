function elf_main2_perEnvironment(dataSet, modules, verbose)
% ELF_MAIN2_PERENVIRONMENT calculates overall ("per-environment") descriptors for each module.
% For the ELF core module, this means calculating the envinroment mean
% image, and the mean intensity descriptors.

%% Set up paths and file names
if nargin < 3, verbose = false; end % verbose determines whether each individual image is plotted during the process, and thumbs are provided at the end
if nargin < 2 , modules = {}; end
if nargin < 1 || isempty(dataSet), error('You have to provide a valid dataset name'); end 

                    
%% Set up paths and file names; read info, infosum and para
elf_paths;
para            = elf_para(modules, '', dataSet);
para            = elf_para_update(para);                      % Combine old parameter file with potentially changed information in current config
infoSum         = elf_io_readwrite(para, 'loadinfosum');      % loads the old infosum file (which contains projection information, and linims)

%% Perform per-environment analysis and plotting for all modules
for i = 1:length(para.modules)
    modPerEnvFilename = [para.modules{i} '_perEnvironment'];
    if ~isempty(which(modPerEnvFilename))
        feval(modPerEnvFilename, para, infoSum, verbose);
    end
end



















