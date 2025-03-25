function elf_callbacks_montage(src, ~)
% elf_callbacks_montage(src, ~)
%
% This is the callback for the ButtonDown function for all montage image objects
% It opens the selected in a new large window (useful to inspect image details)

%% Calculate which image was clicked (column x, row y)
% this is half a point off, but easier than being accurate
cp = get(get(src, 'Parent'), 'currentpoint');
x = floor(cp(1, 1)/100) + 1; 
y = floor(cp(1, 2)/100) + 1;

% Assuming 100 x 100 pixel thumbs, the montag has a x b images
ms = size(get(src, 'CData'));   % montage size in pixels
a = ms(2)/100;                  % number of columns
imnr = (y-1) * a + x;

%% Now load that image and its data
data = get(src, 'UserData');
if imnr<=length(data.fnames_im)
    fname = data.fnames_im{imnr};
    im  = elf_io_readwrite(data.para, 'loadHDR_tif', fname);
    elf_plot_image(im, data.infosum, '', 'equirectangular_summary', 0);
end