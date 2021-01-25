# FISH-IHC 2D colocalization and puncta counting macro

This [Fiji](https://imagej.net/Fiji "Fiji") macro allows a user to perform semi-automated quantification of 2D IHC colocalization and RNAscope puncta counting in fluorescent microscopy images. 

## Installation instructions
* Download the .ijm macro file
* In [Fiji](https://imagej.net/Fiji "Fiji"), install the macro by _Plugins > Install..._ and selecting the .ijm file
* Restart Fiji and the macro will now be an option in the _Plugins_ menu dropdown.

## Use instructions
 1. Put all the images you'd like to analyze within a folder. Upon running the macro, ImageJ will first prompt the user for this folder. 
    * File type for images generally does not matter (e.g., .tif, .czi, .nd2, .lsm will all work).
    * The macro should work on BOTH z-stacks and non-stack images. If using stacks, the macro will perform a maximum intensity projection.
 2. The macro will then create a dialog box for the user to fill out based on the channels present in the current images.
    * The _name_ fields for the IHC channels and probes are optional, but suggested. If filled out, they will appear in the log file that outputs with analysis and also in the output table.
    * Options for segmentation include hand-drawing the cell borders (default if no method is chosen) or autodetecting cells based on a Fiji autothreshold method. 
3. _Advanced Options..._ allow the user to tweak parameters for segmentation and image processing.
    * Automatic thresholding is greatly enhanced with the [Adjustable Watershed plugin](https://imagejdocu.tudor.lu/doku.php?id=plugin:segmentation:adjustable_watershed:start) written by Michael Schmid.
     * Without this plugin, the macro still runs, but will prompt the user to adjust the watershed for each image if an automatic thresholding method is selected. At that point, the user can run the regular watershed function (_Process > Binary > Watershed_) or decide not to watershed and just click _Ok_. 
 4. The output of this macro includes several types of overview images with cell outlines for both channels to assess segmentation and puncta counting accuracy, a .txt log file with information about the parameters used for the analysis to aid reproducibility, and a .csv table with cell measurements, colocalization assessment, and RNAscope puncta counts per cell. 

## Citation
* If using or adapting this macro for your own use, please cite the original authors in any resulting research publications:
    * Benjamin W. Okaty*, Nikita Sturrock*, Yasmin Escobedo Lozoya, YoonJeung Chang, Rebecca A. Senft, Krissy A. Lyon, Olga V. Alekseyenko and Susan M. Dymecki.  A single-cell transcriptomic and anatomic atlas of mouse dorsal raphePet1 neurons. (2020) Elife.
    * Asterisk indicates co-first authorship.
## Error reporting
 * Please report any errors or crashes you receive to [Rebecca Senft](mailto:senftrebecca@gmail.com)

----
