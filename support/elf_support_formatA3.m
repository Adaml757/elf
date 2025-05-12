function figh = elf_support_formatA3(fignum, screenpos)
% figh = elf_support_formatA3(fignum, screenpos)

if nargin < 2
    screenpos = 1;
end
if nargin < 1
    figh = uifigure;
else
    figh = uifigure(fignum);
end

orient(figh, 'landscape');
ss = get(0, 'ScreenSize');       % [1 1 1920 1200]
w  = 2 * (0.9*ss(4)) * 21/29.7;   % width in pixels
h  = 0.9*ss(4);                 % height in pixels               
pos = [1+(screenpos-1)*w  60 w h];

figh.Units = "pixels";
figh.Position = pos;
figh.PaperType = "A3";
figh.PaperUnits = "normalized";
figh.Color = "w";
figh.PaperPositionMode = "auto";
figh.Renderer = "opengl";
% 60 offset if to accommodate Taskbar
