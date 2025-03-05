function res = core_perScene(para, res, im_cal, im_disp, infoSum, iScene, nScenes)
    %CORE_PERSCENE performs scene-by-scene analysis for the CORE module
    %   This is the core ELF intensity calculation; results will later be
    %   averaged across scenes.
    %
    % Inputs:
    %   para    - parameters structure
    %   res     - results structure so far; will be added to
    %   im_cal  - calibrated image for calculations
    %   im_disp - gamma-corrected image, for display only
    %   infoSum - structure with EXIF info
    %   iScene, nScene - number of the current scene, and total number of
    %       scenes, for display and file naming
    % Outputs:
    %   res     - results structure with intensity results added

    if para.ana.calculateInt
        %% Calculate intensity descriptors
        switch para.ana.intAnalysisType
            case 'histcomb' % Calculate histograms for each exposure and combine using conf
                error('Currently not supported!')
    %             [res.core.int, res.core.totalint] = elf_analysis_int(im_HDR_cal, para.ele2(1):para.ele2(2):para.ele2(3), 'histcomb', para.ana.hdivnInt, para.ana.rangePerc, iSet==1, conf_proj, confFactors); % verbose output (analysis parameters) only for the first set
            case 'hdr' % Calculate histograms from HDR image (current default in para)
                [res.int, res.totalint] = elf_analysis_int(im_cal, para.ele2(1):para.ele2(2):para.ele2(3), 'hdr', para.ana.hdivnInt, para.ana.rangePerc, iScene==1); % verbose output (analysis parameters) only for the first set
            otherwise
                error('Unknown intensity calculation method: %s', para.ana.intAnalysisType);
        end
    
        %% Plot summary figure for this scene
        dataSetName = strrep(para.paths.dataset, '\', '\\'); % On PC, paths contain backslashes. Replace them by double backslashes to avoid a warning
        name        = sprintf('%s, scene #%d of %d', dataSetName, iScene, nScenes);
        h           = elf_plot_intSummary(res, im_disp, infoSum, para.plot, name, nScenes);
        set(h.fh, 'Name', sprintf('Scene #%d of %d', iScene, nScenes));
        drawnow;
        
    end  
end

