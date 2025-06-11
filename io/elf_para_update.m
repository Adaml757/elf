function para = elf_para_update(para, currentModule)
%
% currentModule is the name string of the module that is about to be calculated.
% The para.ana.(moduleName) structures of all modules BEFORE and INCULDING
% that module in para.modules will be taken from the new rather than the
% old parameter file. Note that some modules (in their module_analysisPara
% function) overwrite fields in other module's para.ana structs, and these
% changes will not be effective!

if nargin<2, currentModule = []; end

%% Combine old parameter file with potentially changed information in current elf_para
oldpara        = para.fh.loadPara();             % loads the old para file (which contains projection information, too)
oldpara.plot   = para.plot;
oldpara.fh.Paths  = para.fh.Paths;
if ~isempty(currentModule) && ismember(currentModule, para.modules)
    p = find(para.modules==string(currentModule));
    for i = 1:p
        oldpara.ana.(para.modules{i}) = para.ana.(para.modules{i});
    end
end
oldpara.usegpu = para.usegpu;
para           = compStruct(oldpara, para);       % if a field does not exist in oldpara, it is copied from para
