import numpy as np
import matplotlib.pyplot as plt 
from typing import Optional, Union
import numpy as np

def display_img(img: Union[np.ndarray, list], cmap: str = 'gray', figsize: tuple = (10,2), axtitle: Union[str, list] = "", figtitle: str = '', grid = []) -> None:
    """Display one or more images in a large-enough window in a jupyter notebook

    Args:
        img (np.ndarray): The image to display
        cmap (str, optional): Colormap to use for GS images. Defaults to 'gray'.
        figsize (tuple, optional): Figure size for whole grid in inches. Defaults to (10,10).

    Args:
        img (np.ndarray | list): The image or list of images to display
        cmap (str, optional): Colormap to use for GS images. Defaults to 'gray'.
        figsize (tuple, optional): Figure size (w, h) for whole grid in inches. Defaults to (10,2).
        axtitle (str | list, optional): _description_. Defaults to "".
        figtitle (str, optional): _description_. Defaults to ''.

    Raises:
        ValueError: _description_
    """
    if isinstance(img, list):
        imglist = img
    else:
        imglist = [img,]

    if isinstance(axtitle, list):
        axtitlelist = axtitle
    else:
        axtitlelist = len(imglist)*[axtitle,]

    if len(axtitlelist) != len(imglist):
        raise ValueError("The list of images and that of plot titles must be the same length")

    fig = plt.figure(figsize=figsize)
    for i, I in enumerate(imglist):
        ax = fig.add_subplot(1, len(imglist), i+1)
        ax.imshow(I, cmap=cmap)
        if grid:
            # these grids were made in Matlab,  so they are 1-based, not 0-based
            x = [p-1 if p is not None else None for p in grid["x"]]
            y = [p-1 if p is not None else None for p in grid["y"]]
            ax.plot(x, y, "k:")
        if axtitlelist[i]:
            plt.title(axtitlelist[i])
            # ax.set_title(axtitlelist[i])
    if figtitle:
        fig.suptitle(figtitle)
    fig.show()


def display_img_stack(stack: np.ndarray, cmap: str='gray', ncols: Optional[int] = None, figsize: tuple = (24,24), figtitle: str=''):
    """Display an image stack as subplots in a large-enough window in a jupyter notebook

    Args:
        stack (np.ndarray): Image stack as a 3d array (z,y,x) or 4d array (z,y,x,c).
        cmap (str, optional): Colormap to use for GS images. Defaults to 'gray'.
        ncols (int, optional): Number of columns to organise images into. Defaults to None: make a square grid.
        figsize (tuple, optional): Figure size (w, h) for whole grid in inches. Defaults to (24,24).
    """
    if ncols is None:
        ncols = int(np.ceil(np.sqrt(stack.shape[0])))
    nrows = int(np.ceil(stack.shape[0]/ncols))
    fig = plt.figure(figsize=(figsize[0], figsize[1]/ncols*nrows))
    if figtitle:
        fig.suptitle(figtitle)
    for i in range(0, stack.shape[0]):
        ax = fig.add_subplot(nrows, ncols, i+1)
        ax.imshow(stack[i, :, :], cmap=cmap)
        plt.title(f"{i}")
    plt.show()