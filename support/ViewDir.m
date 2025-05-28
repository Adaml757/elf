classdef ViewDir   
    % Enumeration class representing the camera optical axis when an image was taken
    % The azimuth and elevation can be turned as obj.AzEl; the 3d cartesian
    % unit vector as obj.XYZ.
    % 
    % To see all valid values, use enumeration('ViewDir')

    properties
        XYZ(3,1) double
        AzEl(2,1) double
        AzUV(3, 1) double % azimuth unit vector
        ElUV(3, 1) double % elevation unit vector
    end
    
    enumeration
        U  ([ 0; 0; 1], [0; 90], [0; 1; 0], [1; 0; 0])
        D  ([ 0; 0;-1], [0;-90], [0; -1; 0], [1; 0; 0])
        N  ([ 0; 1; 0], [90; 0], [1; 0; 0], [0; 0; 1])
        W  ([-1; 0; 0], [180;0], [0; 1; 0], [0; 0; 1])
        S  ([ 0;-1; 0], [270;0], [-1; 0; 0], [0; 0; 1])
        E  ([ 1; 0; 0], [0;  0], [0; -1; 0], [0; 0; 1])
        H  ([ 1; 0; 0], [0;  0], [0; -1; 0], [0; 0; 1])
        NE ([ sqrt(0.5); sqrt(0.5); 0], [45; 0], [sqrt(0.5); -sqrt(0.5); 0], [0; 0; 1])
        NW ([-sqrt(0.5); sqrt(0.5); 0], [135;0], [sqrt(0.5); sqrt(0.5); 0], [0; 0; 1])
        SW ([-sqrt(0.5);-sqrt(0.5); 0], [225;0], [-sqrt(0.5); sqrt(0.5); 0], [0; 0; 1])
        SE ([ sqrt(0.5);-sqrt(0.5); 0], [315;0], [-sqrt(0.5); -sqrt(0.5); 0], [0; 0; 1])
    end

    methods
        function obj = ViewDir(xyz, azel, azuv, eluv)
            obj.XYZ  = xyz;
            obj.AzEl = azel;
            obj.AzUV = azuv;
            obj.ElUV = eluv;
        end
    end
end