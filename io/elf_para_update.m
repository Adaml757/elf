function para = elf_para_update(para)

%% Combine old parameter file with potentially changed information in current elf_para
oldpara        = para.fh.loadPara();             % loads the old para file (which contains projection information, too)
oldpara.plot   = para.plot;
oldpara.fh.Paths  = para.fh.Paths;
oldpara.usegpu = para.usegpu;
para           = compStruct(oldpara, para);       % if a field does not exist in oldpara, it is copied from para
