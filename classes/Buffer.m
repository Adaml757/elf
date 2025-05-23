classdef Buffer < handle
    
    properties (Constant)
        B = BufferMemory
    end
    
    methods
        %% constructor
        function obj = Buffer()            
        end
    end
    
    %% public static methods    
    methods (Static)
        function store(name, deps, bufferObj)
            % Stores object "bufferObj" and its dependencies "deps" in the buffer with the name "name"
            b = Buffer.B;
            b.Name = name;
            b.Dependencies = deps;
            b.Object = bufferObj;
        end
        
        function bufferedObj = retrieve(name, deps)
            % Retrieves the object stored in the buffer with name "name" if its stored dependencies equal "deps"; otherwise, returns []
            b = Buffer.B;
            if isequal(b.Name, name) && isequal(b.Dependencies, deps)
                bufferedObj = b.Object;
            else
                bufferedObj = [];
            end
        end
    end
end

