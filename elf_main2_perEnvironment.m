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
for i = length(para.modules):-1:1
    % run through modules in reverse order (i.e. dependencies before main modules
    if para.ana.(para.modules{i}).needsToRunPerEnvironment
        modPerEnvFilename = [para.modules{i} '_perEnvironment'];
        [para, infoSum] = feval(modPerEnvFilename, para, infoSum, verbose);
        elf_io_readwrite(para, 'saveinfosum', [], infoSum); % saves infosum AND para for use in later stages
    end
end



















