function needsToRun = core_needsToRun(anaP)
% CORE_NEEDSTORUN tells elf_main2_perEnvironment and elf_maingui whether
% this module's perEnvironment function needs to run based on para.
% If not, not button will be created for it
    needsToRun = anaP.calculateMeanImage || anaP.calculateInt;
end

