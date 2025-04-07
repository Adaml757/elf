classdef ViewDir   
    % Enumeration class representing the camera optical axis when an image was taken
    % The azimuth and elevation can be turned as obj.AzEl; the 3d cartesian
    % unit vector as obj.XYZ.
    % 
    % To see all valid values, use enumeration('ViewDir')

    properties
        XYZ(3,1) double
        AzEl(2,1) double
    end
    
    enumeration
        U  ([ 0; 0; 1], [0; 90])
        D  ([ 0; 0;-1], [0;-90])
        N  ([ 0; 1; 0], [90; 0])
        W  ([-1; 0; 0], [180;0])
        S  ([ 0;-1; 0], [270;0])
        E  ([ 1; 0; 0], [0;  0])
        NE ([ sqrt(0.5); sqrt(0.5); 0], [45; 0])
        NW ([-sqrt(0.5); sqrt(0.5); 0], [135;0])
        SW ([-sqrt(0.5);-sqrt(0.5); 0], [225;0])
        SE ([ sqrt(0.5);-sqrt(0.5); 0], [315;0])
    end

     methods
         function obj = ViewDir(xyz, azel)
            obj.XYZ  = xyz;
            obj.AzEl = azel;
        end
     end
end