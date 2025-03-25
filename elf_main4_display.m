function elf_main4_display(dataSet, modules)
% ELF_MAIN4_DISPLAY simply displays the intensity mean and mean image for a dataset
%
% elf_main4_display(dataSet, imgFormat)

if nargin < 2, modules = {}; end

          elf_paths;
para    = elf_para(modules, '', dataSet);
          elf_main2_perEnvironment(dataSet, modules)





