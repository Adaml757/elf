function anaP = core_analysisPara(d)
    % translate .env parameters for the CORE module

    anaParameters = ...
        {'RESOLUTION_BOOSTER', 'double';
        'CALCULATE_INT', 'logical';
        'CALCULATE_MEAN_IMAGE', 'logical';
        'IMAGE_DIRECTION', 'string';
        'IMAGE_ROTATION', 'double';
        'TARGET_PROJECTION', 'string';
        'TARGET_AZI_RANGE', 'doublevector';
        'TARGET_ELE_RANGE', 'doublevector';
        'HDIVN_INT', 'double';
        'RANGE_PERC', 'double';
        'COLOUR_CALIB_TYPE', 'string';
        'INT_ANALYSIS_TYPE', 'string';
        'HDR_METHOD', 'string';
        'VALID_IMAGE_RADIUS', 'double';
        'TARGET_IMAGE_SIZE', 'doublevector';
        'SAVE_SCENE_TIFS', 'logical';
        'SAVE_DIAGNOSTIC_TIFS', 'logical'};

    anaP = d.extractValues('ANALYSIS', anaParameters);
    anaP.version = str2double(d.Env.VERSION);

    if isempty(anaP.resolutionBooster) || anaP.resolutionBooster ~= round(anaP.resolutionBooster) || anaP.resolutionBooster<=0 || anaP.resolutionBooster>10
        error('Invalid value found for ANALYSIS_RESOLUTION_BOOSTER');
    end
    if numel(anaP.targetAziRange)~=2
        error("ANALYSIS_TARGET_AZI_RANGE needs to have exactly two elements");
    end
    if numel(anaP.targetEleRange)~=2
        error("ANALYSIS_TARGET_ELE_RANGE needs to have exactly two elements");
    end
    if numel(anaP.targetImageSize)~=3
        error("ANALYSIS_TARGET_IMAGE_SIZE needs to have exactly three elements");
    end
    anaP.imageDirection = ViewDir(anaP.imageDirection);
end