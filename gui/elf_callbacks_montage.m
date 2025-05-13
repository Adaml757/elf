function elf_callbacks_montage(src, ~, type)
% elf_callbacks_montage(src, ~)
%
% This is the callback for the ButtonDown function for all montage image objects
% It opens the selected in a new large window (useful to inspect image details)

if nargin<3, type = 'HDR'; end
    
%% Calculate which image was clicked (column x, row y)
% this is half a point off, but easier than being accurate
cp = get(get(src, 'Parent'), 'currentpoint');
x = floor(cp(1, 1)/100) + 1; 
y = floor(cp(1, 2)/100) + 1;

% Assuming 100 x 100 pixel thumbs, the montag has a x b images
ms = size(get(src, 'CData'));   % montage size in pixels
a = floor(ms(2)/100);                  % number of columns
imnr = (y-1) * a + x;

%% Now load that image and its data
data = get(src, 'UserData');
if imnr<=length(data.fnames_im)
    fname = data.fnames_im{imnr};
    switch type
        case "diag"
            im = data.para.fh.loadSceneDiag_tif(fname);
        case "HDR"
            im = data.para.fh.loadScene_tif(fname);
    end
    switch data.para.ana.targetProjection
        case "equirectangular"
            elf_plot_image(im, data.infosum, '', 'equirectangular_summary', 0);
        case {"equisolid", "equidistant", "orthographic", "stereographic"}
            elf_plot_image(im, data.infosum, '', ['equisolid_' type], 0);
        otherwise
            error("Summary images for %s projection not yet implemented")
    end
    if type=="diag"
        text(size(im, 1)-10, 10, ...
            sprintf("{\\color{red}Saturation}\n{\\color{green}Low Signal}\n{\\color{blue}Movement}"), ...
            "Color", "w", "HorizontalAlignment", "right", "VerticalAlignment", "top", "FontWeight", "bold", "Interpreter", "tex", "FontSize", 16)
    end
end