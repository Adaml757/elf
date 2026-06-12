function elf_callbacks_elfgui(src, ~)
% elf_callbacks_elfgui(src, ~)
%
% This is the callback for the gui elements on an ELF results sheet

switch get(src, 'tag')
    case {'gui_posslider', 'gui_rangeslider'}
        newwidth = get(findobj('tag', 'gui_rangeslider'), 'Value');       % between -1 and 1, log10 of x-axis width
        medcentre = get(findobj('tag', 'gui_posslider'), 'UserData');       % log10 of x-axis pos centre
        newcentre = medcentre + get(findobj('tag', 'gui_posslider'), 'Value');       % between -4 and 4, log10 of x-axis pos offset
        ax1 = findobj('tag', 'gui_ax1');
        ax3 = findobj('tag', 'gui_ax3');
        ax4 = findobj('tag', 'gui_ax4');
        newax = [10^(newcentre - newwidth/2) 10^(newcentre + newwidth/2)];
        xlim(ax1, newax);
        xlim(ax3, newax);
        xlim(ax4, newax);
    otherwise
        %ignore for now
end

