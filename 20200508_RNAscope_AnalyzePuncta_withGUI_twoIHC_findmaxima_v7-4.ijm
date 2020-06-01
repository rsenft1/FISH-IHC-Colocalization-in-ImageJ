//RNAscope-IHC puncta analysis Script FIND MAXIMA EDITION 1 mask 2 Probes
//Rebecca Senft 1/16/19
//Version history
//1.30.19 - added automatic segmentation option
//2.4.19 - enhance contrast during automatic cell count to get better looking cell mask output images.
//2.7.9  -  made two IHC, 1 probe version, added in negative control option
//2.12.19 - fixed issues with detecting cell IHC overlap and allowed for both automated and hand-picked cell detection, neg control removed
//2.15.19 - added multimeasure of ROIs to improve speed of Find Maxima and area measurements
//2.16.19 - finished instructions
//3.25.20 - made more modular by rewriting with functions
//4.01.20 - fixed issue with mac and pc computers having different color background for single points output of find maxima for puncta counting. 
//4.10.20 - added BG subtraction step for cell bodies based on issues with a dim staining rostral DR; also added in 
//			ability to make the screen toggle the rois during manual deletion and inclusion of a reference image without ROIs present
//			to make selection of the badly segmented rois easier. Also changed default for gaussian blur sigma to 2 (seemed better)
//4.11.20 - fixed preference issue where some machines defaulted to not ignoring source LUTS when merging. v 5.2 also resizes windows before
//			manual editing begins. 
//4.12.20 - fixed issue with colocOverlay not having persistent outlines for Ch1 in output image. 
//5.08.20 - added in shape parameters, removed the intensity parameters gathered separately for Ch2 (now will always report Ch2 even for Ch1 ROIs), 
//          and added in ability to discount overlapping sections of non-colocalized Ch1 cells (i.e. if a Ch1 cell is close to Ch2 cell such that 
//			in the projection, some portion is overlapping, but the cell itself is not positive for the Ch2 stain, this will not count puncta in
//			the portion of the cell overlapping with the Ch2 cell (avoid false positive puncta count).
//			VERSION 6 - original manual deletion and drawing of ROIs still separate and sequential
//			VERSION 7 - ROI editing is one step with click and delete and redrawing all courtesy of the ROI manager
//				v7-2 reverted to cell numbers for manual editing instead of ROI name. 
//				v7-3 fixed issue with exclude overlap deleting a previously-selected Ch1 ROI in addition to the merged Ch2 ROI
//				v7-4 fixed issue with batch mode causing a console error.
/*
 * Instructions:
 * 
 * PLEASE READ
 * 
 * Upon running, ImageJ will ask for a folder. Put all the images you'd like to analyze within a folder. 
 * It generally doesn't matter what file type they are (e.g. tif, czi, nd2, lsm will all work). It also doesn't
 * matter if there are other file types in the folder. ImageJ will ignore them.  
 * 
 * Macro should work on BOTH stacks and non-stack images
 * 
 * The names for the IHC channels and probes are optional, but if you want them they will appear in the 
 * log file that outputs with analysis.
 * 
 * Options include hand-drawing the cell borders (default) or autodetecting cells based on an autothreshold method. 
 * The automatic thresholding requires the Adjustable Watershed plugin written by Michael Schmid to work best. To download, see: 
 * https://imagejdocu.tudor.lu/doku.php?id=plugin:segmentation:adjustable_watershed:start
 * Download that and then you can tweak ImageJ's watershedding to be best for your cells. 
 * If not, it still works, but will ask you to adjust the watershed for each image. At that point, you can 
 * run the regular watershed function (Process > Binary > Watershed) or decide not to watershed. 
 * 
 * The output of this program includes overview images with cell outlines for both channels, a table of measurements of 
 * cells in both channels as well as a colocalization column to indicate of cells in both channels are colocalized (by overlap).
 * 
 * Please report any errors or crashes you get to Rebecca Senft (senftrebecca@gmail.com)
 */
 
//***********************************************	
//Step 0. Select directory of images to analyze
//***********************************************	
macro "IHC Coloc + RNAscope puncta Counting - RS" {
	//0.1 get directory with images and create the output directories
	run("Close All");
	dir= getDirectory("Choose a Directory") //select your folder with images
	list=getFileList(dir);
	roiDir=dir+"ROIs/";
	date=getDate();
	File.makeDirectory(dir + date+"_RNAscopeIHCanalysis/"); 
	dirSave=dir + date+"_RNAscopeIHCanalysis/";
	File.makeDirectory(dirSave + "savedOverlays/"); 
	imageDir=dirSave + "savedOverlays/";
	File.makeDirectory(dirSave + "CSV_Files/"); 
	csvDir=dirSave + "CSV_Files/";
	files=newArray();
	saveType="Tiff";
	print("\\Clear"); //clears log
	roiManager("UseNames", "false"); //unless manually editing ROIs this doesn't help usually.
	
	//0.2 Initialize for output table:
	fileNames=newArray();
	cellNumber=newArray();
	allAreas=newArray();
	Puncta1=newArray();
	colocArrayTotal=newArray();
	cellMark1=newArray();
	cellMark2=newArray();
	deleteROIs=newArray();
	
	//0.3 Dialog boxes
	title="none";
	channelList=newArray("none","C1-", "C2-", "C3-","C4-");
	thresList=newArray("No threshold","Triangle", "Default", "Huang", "Otsu", "MaxEntropy");
	probeList=newArray();
	Dialog.create("Select Channels");
	Dialog.addChoice("IHC channel 1", channelList);
	Dialog.addChoice("IHC channel 2", channelList);
	Dialog.addChoice("Probe channel 1", channelList);
	Dialog.addChoice("DAPI channel", channelList);
	Dialog.addString("Label for IHC Channel 1 (optional):", title);
	Dialog.addString("Label for IHC Channel 2 (optional):", title);
	Dialog.addString("Label for Probe (optional):", title);
	Dialog.addChoice("Threshold Method for IHC 1", thresList);
	Dialog.addChoice("Threshold Method for IHC 2", thresList);
	Dialog.addCheckbox("Exclude overlapping portion of non-colocalized Ch1 cells?",false);
	Dialog.addCheckbox("Manual check and editing of ROIs?",false);
	Dialog.addCheckbox("Advanced options...",false);
	Dialog.show();
	maskChannel=Dialog.getChoice;
	IHCChannel = Dialog.getChoice;
	probe1Channel = Dialog.getChoice;
	DAPI=Dialog.getChoice;
	mask1Name=Dialog.getString;
	mask2Name=Dialog.getString;
	probe1Name=Dialog.getString;
	thresh1 = Dialog.getChoice;
	thresh2 = Dialog.getChoice;
	exclude = Dialog.getCheckbox();
	manualEdit = Dialog.getCheckbox();
	advanced = Dialog.getCheckbox();
	//
	if (advanced){
		Dialog.create("Advanced options...");
		Dialog.addNumber("Rolling ball BG subtract ball size (in pixels; for auto cell detection)",100);
		Dialog.addNumber("Gaussian blur sigma (for auto cell detection)",2);
		Dialog.addNumber("Cell area minimum (for auto cell detection)",70);
		Dialog.addNumber("Adjustable watershed tolerance (for splitting cells during segmentation). Leave 0 to adjust manually per image",0);
		Dialog.addNumber("Overlap minimum (for colocalization)",60);
		Dialog.addNumber("Minimum cell circularity (for auto cell detection)",0.3);
		Dialog.addNumber("Rolling ball BG subtration ball size (for RNAscope puncta)",50);
		Dialog.addNumber("Find maxima prominence (for RNAscope puncta)",100);
		Dialog.show();
		RBC = Dialog.getNumber();
		GB = Dialog.getNumber();
		CA = Dialog.getNumber();
		adjustWatershed=Dialog.getNumber();
		areaPercent = Dialog.getNumber();
		MC = Dialog.getNumber();
		RBP = Dialog.getNumber();
		MP = Dialog.getNumber();
	}
	else{
		RBC = 100; 
		GB = 2;
		CA = 70;
		adjustWatershed=0;
		areaPercent = 60;
		MC = 0.3;
		RBP = 50;
		MP = 100;
	}
	//testcode:
	//maskChannel="C3-";
	//IHCChannel = "C1-";
	//probe1Channel = "C2-";
	//DAPI="C4-";
	//0.4 Error check to ensure there are enough channels selected!
	if (maskChannel=="none"){
		exit("Error: ensure there is a channel selected for a cell mask");
	}
	if (IHCChannel=="none"){
		exit("Error: ensure there is a second channel selected for a cell mask");
	}
	if (probe1Channel=="none"){
		exit("Error: ensure there is a channel selected for Probe 1");
	}
	
	//0.5 Initialize Log File
	run("Set Measurements...", "area mean min shape integrated median area_fraction limit display redirect=None decimal=6");
	print("*******************************************************************************************************************************************");
	print("RNAscope-IHC Find Maxima Analysis Date: "+date);
	print("Script: 20200401_RNAscope_AnalyzePuncta_withGUI_twoIHC_findmaxima_v7-4");
	print("*******************************************************************************************************************************************");
	if (mask1Name==title){
		mask1Name="Ch1";
	}
	if (mask2Name==title){
		mask2Name="Ch2";
	}

	if (probe1Name==title){
		probe1Name="Probe1";
	}
	print("IHC Channel 1: "+ maskChannel+"Immuno for "+mask1Name);
	print("IHC Channel 2: "+ IHCChannel+"Immuno for "+mask2Name); 
	print("Probe 1: "+ probe1Channel+probe1Name);
	print("Threshold for IHC 1: "+thresh1);
	print("Threshold for IHC 2: "+thresh2);
	print("Manual editing of ROIs? "+manualEdit);
	print("Exclude overlapping portion of non-colocalized Ch1 cells? "+exclude);
	print("");
	if (advanced){
		print("ADVANCED OPTIONS SELECTED");
	}
	else{
		print("NO ADVANCED OPTIONS CHOSEN");
	}
	print("Cell rolling ball size (pixels) - "+RBC);
	print("Gaussian blur sigma - "+GB);
	print("Cell area min - "+CA);
	print("Adjustable watershed tolerance (0 = manual) - "+adjustWatershed);
	print("Minimum area overlap for colocalization - "+areaPercent);
	print("RNAscope rolling ball size (pixels) - "+RBP);
	print("Find maxima puncta prominence - "+MP);
	//setBatchMode(true); 
	
	//***********************************************	
	//Step 1: Open Images to analyze
	//***********************************************	
	for (i=0;i<list.length; i++){
		if((endsWith(list[i],".czi"))||(endsWith(list[i],".tif"))||(endsWith(list[i],".lsm"))||(endsWith(list[i],".nd2"))||(endsWith(list[i],".tiff"))){
		files=Array.concat(files,list[i]);
	}
	}
	NumCells = newArray(files.length);
	for (k=0;k<files.length; k++){
		//setBatchMode(false);
		run("Bio-Formats Windowless Importer", "open=["+dir+files[k]+"]");
		name=File.name; 
		saveName=File.nameWithoutExtension;
		Areas=newArray();
		print("*******************************************************************************************************************************************");
		print("File "+k+1+": "+name);
		probe1=probe1Channel+name;
		mask=maskChannel+name;	
		mask2=IHCChannel+name;
		getDimensions(w, h, channels, sliceCount, dummy);
		//If z stack, then make max projection first
		if (sliceCount>1){ 
			run("Z Project...", "projection=[Max Intensity]");
			selectWindow(name);
			rename("stack");
			selectWindow("MAX_"+name);
			rename(name);
		}
		run("Split Channels");
		
	///***********************************************	
	//Step 2. Selecting cells for mask 1
	//***********************************************
		//Initialize variables
		roiManager("reset");
		chArray = newArray(0);
		cellArray = newArray(0);
		cell1Array = newArray(0);
		cell2Array = newArray(0);
		ImageArray = newArray(0);
		cellIntArray1 = newArray(0);
		cellIntArray2 = newArray(0);
		//2.1 Apply ROIs from file if present
		if (File.exists(roiDir+saveName+"_Ch1_roi.zip")==1){
			open(roiDir+saveName+"_Ch1_roi.zip");
			//roiManager("Add"); 
			print("ROIs found for Ch1");
		}
		else{
			threshold(mask, thresh1, DAPI, name, 1);
		}
		if(manualEdit==true){
			manualEditRois(roiDir, 1, mask, saveName,imageDir);
		}
		roiManager("reset");
		open(roiDir+saveName+"_Ch1_roi.zip");
		//waitForUser("ROICHECK");
		ch1CellNum=roiManager("count");
		print("# Ch1 Cells: "+ch1CellNum);
		
		for (i=0; i<ch1CellNum; i++){
			chArray=Array.concat(chArray, mask1Name); //append channel names to list
			cell1Array=Array.concat(cell1Array,i);
		}
	
	//***********************************************	
	//Step 3. Selecting cells for mask 2
	//***********************************************	
	//3.1 Apply ROIs from file if present
		roiManager("reset");
		if (File.exists(roiDir+saveName+"_Ch2_roi.zip")==1){
			open(roiDir+saveName+"_Ch2_roi.zip");
			//roiManager("Add"); 
			print("ROIs found for Ch2");
		}
		else{
			//perform thresholding
			threshold(mask2, thresh2, DAPI, name, 2);
			}
		if(manualEdit==true){
			//or skip straight to manually drawing ROIs
			manualEditRois(roiDir, 2, mask2, saveName,imageDir);
		}
		roiManager("reset");
		open(roiDir+saveName+"_Ch2_roi.zip");
		ch2CellNum=roiManager("count");
		print("# Ch2 Cells: "+ch2CellNum);
		//Generate arrays for the data table output
		for (i=0; i<ch2CellNum; i++){
			chArray=Array.concat(chArray, mask2Name);
			cell2Array=Array.concat(cell2Array,i+ch1CellNum);
		}
		for (i=0; i<(ch1CellNum+ch2CellNum); i++){
			cellArray = Array.concat(cellArray, i+1);
			ImageArray = Array.concat(ImageArray,saveName);
		}

	//***********************************************	
	//Step 4. Assess which cells are co-positive in both IHC channels
	//***********************************************	
		//4.1 Check which cells in Ch1 are colocalized with Ch2 (and vice versa)
		overlap1 = computeOverlap(roiDir,saveName,1,2,ch1CellNum);
		overlap2 = computeOverlap(roiDir,saveName,2,1,ch2CellNum);
		//concatenate overlap arrays together
		overlapArrayTotal=Array.concat(overlap1,overlap2);
		//Get indices that should be deleted to avoid double counting cells in Ch1 and Ch2 (deletions will occur in Ch2)
		deleteROIs = removeColocCh2(roiDir,ch1CellNum,ch2CellNum,overlap1,areaPercent,w*h);
		//Delete these indices in arrays generated so far (remember can't just delete the ROIs because we want them for completion.
		overlapArrayTotal= deletePosition(overlapArrayTotal,deleteROIs);
		cellArray= deletePosition(cellArray,deleteROIs);
		chArray=deletePosition(chArray,deleteROIs);
		ImageArray=deletePosition(ImageArray,deleteROIs);
		//Colocalization binary variable:
		colocTotal=newArray(0);
		for(i=0;i<lengthOf(overlapArrayTotal);i++){
			if(overlapArrayTotal[i]>areaPercent){
				colocTotal = Array.concat(colocTotal,1);
			}
			else{
				colocTotal = Array.concat(colocTotal,0);
			}
		}
		//4.2 Overlay generation
		overlapOverlay(mask, mask2, roiDir, cell2Array, imageDir);
		//if desired, get rid of overlapping portions of Ch1 ROIs that partially overlap with Ch2 but do not meet colocalization threshold. 
		if (exclude==true){
			excludeOverlap(dirSave, roiDir, imageDir, saveName, 1, 2, overlap1, areaPercent);
		}
		//Get intden from both Ch1 and Ch2 for all ROIs
		cellIntArray2 = getIntensity(roiDir, mask2, cellIntArray2);
		cellIntArray1 = getIntensity(roiDir, mask, cellIntArray1);
		//Again perform same deletion for the second instance of each colocalized cell in the ROI list (remember each colocalized cell has 1 Ch1 ROI and 1 Ch2 ROI
		cellIntArray2 = deletePosition(cellIntArray2,deleteROIs);
		cellIntArray1 = deletePosition(cellIntArray1,deleteROIs);
		//4.3 Begin the table!
		roiManager("reset");
		open(roiDir+saveName+"_Ch1_roi.zip");
		open(roiDir+saveName+"_Ch2_roi.zip");
		if(lengthOf(deleteROIs)>0){
			roiManager("select",deleteROIs);
			roiManager("delete");
		}
		roiManager("multi-measure append");
		addToTable(ImageArray,"Image");
		addToTable(cellArray,"Cell ID");
		addToTable(chArray,"Channel");
		addToTable(colocTotal,"Colocalized?"); //need to make sure this only adds in the cells that are deemed necessary and not overcount!!! don't doublecount colocalized cells
		addToTable(overlapArrayTotal,"% Area overlap");
		addToTable(cellIntArray1, mask1Name+" IntDen");
		addToTable(cellIntArray2, mask2Name+" IntDen");
		IJ.renameResults("temp"); //need to store these for later...
	
	//***********************************************	
	//Step 5. Isolate Puncta in RNAscope channel and preprocessing
	//***********************************************	
		selectWindow(probe1);
		run("Subtract Background...", "rolling="+RBP);
		
	//***********************************************	
	//Step 6. Analyze particles to gather # of RNAscope puncta
	//***********************************************	
		//count puncta in ROIs in Ch1
		puncta1 = punctaCount(saveName, roiDir, 1, probe1);
		//Count puncta for ROIs in Ch2
		puncta2 = punctaCount(saveName, roiDir, 2, probe1);
		//Concatenate Ch1 and Ch2 lists
		punctaTotal=Array.concat(puncta1, puncta2);
		//Delete second repeat instance for colocalized cells
		punctaTotal=deletePosition(punctaTotal,deleteROIs);
		//generate overlay image
		punctaOverlay(probe1,mask,cell1Array);
		run("Close All");
	//***********************************************	
	//Step 7. Generate Final Results Table
	//***********************************************	
		closeIfOpen("Results");
		Table.rename("temp", "Results");
		addToTable(punctaTotal,"# Puncta");
		saveAs("Results",csvDir+date+"_"+saveName+"_Results.csv");
		run("Close All");
		closeIfOpen("temp");
		closeIfOpen("Results");
	}
	//save log file as well for metadata.
	selectWindow("Log");
	saveAs("Text",dirSave+date+"_analysisMetadata.txt");
}
	//***********************************************	
	// FUNCTIONS
	//***********************************************	

	function closeWindow(window){
		//this function closes a given window by its title
		selectWindow(window);
		close();
	}
	function getDate(){
		//This function gets and returns a string of the current date in yearmonthday format.
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		if (dayOfMonth<10) {dayOfMonth = "0"+dayOfMonth;}
		month=month+1;
		if (month<10) {month = "0"+month;}
		return toString(year)+toString(month)+toString(dayOfMonth);
	}
	function autoThreshold(autoMask, thresh){
		/*This function will threshold a mask channel automatically given a specific autothreshold method given 
		 * by thresh variable. Also performs basic preprocessing including a gaussian blur, a closure operation, filling of holes, 
		 * and the option per image for the user to adjust a watershed variable. 
		 * Note that the adjustable watershed plugin has to be installed in order to use the adjustable watershed command.
		 * If desired, the line with 'run("Adjustable watershed," tolerance=1) can be used instead of the waitForUser if
		 * a single adjustable watershed level is desired for every cell. 
		 * Finally, performs a filter based on size of cell.
		 * No outputs.
		 */
	 	roiManager("reset");
		selectWindow(autoMask);
		run("Duplicate...", "title=2");
		//run("Enhance Contrast", "saturated=0.35");
		selectWindow("2");
		run("Subtract Background...", "rolling="+RBC);
		run("Gaussian Blur...", "sigma="+GB);
		setAutoThreshold(thresh+" dark no-reset");
		run("Convert to Mask");
		run("Close-");
		run("Fill Holes");
		selectWindow("2");
		if (adjustWatershed!=0){
			run("Adjustable Watershed", "tolerance="+adjustWatershed);
		}
		else{
			waitForUser("Adjust Adjustable watershed if desired");
		}
		//run("Adjustable Watershed...", "tolerance=3");
		run("Analyze Particles...", "size="+CA+"-Infinity circularity="+MC+"-1.00 display clear include add");
		selectWindow("2");
		run("Close");
	}
	function manualThreshold(MyMask, DAPI, name){
		/*This function allows the user to hand draw rois. If a DAPI channel is 
		 * specified, it will overlay DAPI in magenta along with the channel to form ROIs from in green. 
		 * No outputs
		 */
		roiManager("reset");
		run("ROI Manager...");
		roiManager("Show All with labels");
		selectWindow(MyMask);
		if (DAPI!="none"){
			selectWindow(DAPI+name);
			run("Enhance Contrast", "saturated=0.35");
			run("Merge Channels...", "c2=["+MyMask+"] c6=["+DAPI+name+"] create keep ignore");
			run("Enhance Contrast", "saturated=0.4");
			//run("Enhance Contrast", "saturated=0.35");
			rename("temp");
		}
		else{
			selectWindow(MyMask);
			run("Duplicate...","title=temp");
		}
		selectWindow("temp"); 
		setTool("freehand");
		roiManager("Show All with labels");
		selectWindow("temp");
		waitForUser("Use freehand tool to outline visible cells, then hit 't' to add to ROI manager");
		run("Close");
	}
	function threshold(MyMask, myThresh, DAPI, name, Ch){
		/*This function will send images to be thresholded via automatic or manual means depending on 
		 * the value of an autoThres variable).
		 * No outputs, but saves the generated ROIs in the ROI directory and calls other functions for 
		 * thresholding and saving overview images.
		 */
		//Automatic Mask
		roiManager("reset");
		if (myThresh!="No threshold"){
			autoThreshold(MyMask, myThresh); 
		}
		//Manual Mask
		else {
			manualThreshold(MyMask, DAPI, name);
		}
		File.makeDirectory(roiDir);
		roiManager("save", roiDir+"/"+saveName+"_Ch"+Ch+"_roi.zip");
		saveOverview(MyMask,saveName,imageDir,Ch);
	}
	function manualEditRois(roiDir, Ch, imageWindow,saveName,imageDir){
		/*This function will display ROIs to the user, allow them to input which ones they would like to change,
		 * and store the changes in new roi files and a new indexing string. This function should be done before
		 * any other computation or measurement because it may change the ordering of the ROIs.
		 * SIMPLE VERSION
		 * No outputs, but calls saveOverview to save overview image.
		 */
		 roiManager("reset");
		 roiManager("Show All with labels");
		 //roiManager("UseNames", "true");
		 run("Labels...", "color=white font=12 show draw");//takes roimanager's settings for line color and width
		 selectWindow(imageWindow);
		 run("Duplicate...","title=reference");
		 if (DAPI!="none"){
			selectWindow(DAPI+name);
			run("Enhance Contrast", "saturated=0.4");
			run("Merge Channels...", "c2=reference c6=["+DAPI+name+"] create keep ignore");
			run("Enhance Contrast", "saturated=0.35");
			rename("merge");
			closeWindow("reference");
			selectWindow("merge");
			rename("reference");
		 }
		 selectWindow(imageWindow);
		 open(roiDir+saveName+"_Ch"+Ch+"_roi.zip"); //select rois to open
		 selectWindow("reference");
		 roiManager("Show All with labels");
		 run("Brightness/Contrast...");
		 run("Channels Tool...");
		 //if the file is a z stack, arrange next to the stack image so user can easily see both.
		 if (isOpen("stack")){
		 	resizeThree("reference", "stack","ROI Manager");
		 }
		 else{
		 	resizeTwo("reference","ROI Manager");
		 }
		 setTool("freehand");
		 selectWindow("reference");
		 roiManager("Show All with labels");
		 waitForUser("Please edit ROIs. You can click and delete ROIs from the image using 'Delete' in ROI Manager \nand draw new ROIs by using a selection tool then hitting 't' to add to manager");	
 		 roiManager("save", roiDir+"/"+saveName+"_Ch"+Ch+"_roi.zip");
 		 run("Select None");
 		 closeIfOpen("reference");
		 saveOverview(imageWindow,saveName,imageDir,Ch); 
	}
	function resizeTwo(win1,win2){
		/*
		 * This function resizes two windows to better fit the screen space available. 
		 * No outputs. Win1 should be image and win2 a text menu
		 * Also moves B&C window
		 */
		getLocationAndSize(x, y, pixelwidth, pixelheight);
		selectWindow(win1); //must be image
		setLocation(20, 20, screenWidth/2, screenHeight);
		selectWindow(win2); //must be menu
		setLocation((screenWidth/2)+10, screenHeight/3);
		selectWindow("B&C");
		setLocation((screenWidth/2)+10, screenHeight/2);
		selectWindow("Channels");
		setLocation((screenWidth/2)+200, screenHeight/2);
	}
	function resizeThree(win1,win2,win3){
		/*
		 * This function resizes two windows to better fit the screen space available. 
		 * No outputs.Third window is menu
		 * Also moves B&C window
		 */
		getLocationAndSize(x, y, pixelwidth, pixelheight);
		x1=20;
		y1=20;
		x2=screenWidth/3+20;
		x3=(screenWidth*2/3)+20;
		selectWindow(win1); //must be image
		setLocation(x1, y1, screenWidth/3, screenHeight);
		selectWindow(win2); //must be image
		setLocation(x2, y1, screenWidth/3, screenHeight);
		selectWindow(win3); //must be menu 
		setLocation(x3, screenHeight/3);
		selectWindow("B&C");
		setLocation(x3, screenHeight/2);
		selectWindow("Channels");
		setLocation(x3+200, screenHeight/2);
	}
	function saveOverview(Mask,saveName, imageDir, Ch){
		/*This function is used to save overlays of ROIs currently open on top of a channel 
		 * given by the variable mask. No output, but saves the overlay images to imageDir.
		 */
		selectWindow(Mask);
		run("Original Scale");
		run("Duplicate...", "title="+Mask+"_cellOutlines");
		roiManager("Show All with labels");
		run("Overlay Options...", "stroke=yellow width=0 fill=none set");
		if(Ch==1){
			roiManager("Set Color", "orange");
		}
		else{
			roiManager("Set Color","green");
		}
		roiManager("Set Line Width", 5);
		run("From ROI Manager");
		run("Labels...", "color=white font=24 show draw");//takes roimanager's settings for line color and width
		run("Flatten");
		saveAs(saveType,imageDir+saveName+"_"+Ch+"_cellOutlines.tiff");
		run("Close");
	}
	function computeOverlap(roiDir,saveName,Ch1,Ch2,CellNum){
		/*This function opens rois contained in the roiDir path of Ch2, then combines them into a mask, 
		 * then opens Ch1 rois and asks what is the overlap of each ROI in Ch1 with the mask of Ch2.
		 * OUTPUT: Returns an array of the overlap in percent area overlapping for each ROI in Ch1.
		 * Also saves the mask image for Ch2 for use with excludeOverlap(optional)
		 */
		run("Clear Results");
		colocArray=newArray();
		overlapArray=newArray();
		roiManager("reset");
		open(roiDir+saveName+"_Ch"+Ch2+"_roi.zip"); // secondary channel, less important
		roiManager("Select all");
		if(roiManager("count")>1){
			roiManager("Combine");
		}
		else{
			roiManager("select",0); //if only 1 ROI, must select it specifically before making a mask
		}
		run("Create Mask"); //name is "Mask"
		selectWindow("Mask");
		run("Duplicate...","title=2");
		selectWindow("2");
		saveAs(saveType,imageDir+saveName+"_"+Ch2+"_mask.tiff"); //saves the mask (useful for excluding overlap if desired)
		run("Close");
		roiManager("reset");
		open(roiDir+saveName+"_Ch"+Ch1+"_roi.zip"); // primary channel for colocalization
		for (i=0; i<CellNum; i++){
			selectWindow("Mask");
			roiManager("select", i);
			run("Measure");
			overlapArray= Array.concat(overlapArray,getResult("%Area",i));
		}
		selectWindow("Mask");
		run("Close");
		return overlapArray;
	}
	function excludeOverlap(dirSave, roiDir, imageDir, saveName, Ch1, Ch2, overlapArray,colocThres){
		/*
		 * This function examines ROIs of the first channel for their overlap with ROIs of the second channel and 
		 * if they do not meet the colocalization overlap threshold, this function will delete the intersecting
		 * portion of Ch1 ROIs that overlap with Ch2.  
		 * The Channels should be treated as if they are hard-coded or else it may break ...
		 * Ch1 should always be the the channel of more interest.
		 * No outputs but calls saveOverview to save a new overlay image in a separate folder within the imageDir.
		 */
		roiManager("reset");
		open(roiDir+saveName+"_Ch"+Ch1+"_roi.zip"); // open original ROIs for Ch1
		Ch1Num = roiManager("count");
		//print("Ch1 #:"+Ch1Num);
		open(imageDir+saveName+"_"+Ch2+"_mask.tiff");
		setAutoThreshold("Default dark");
		run("Threshold..."); //this highlights all white pixels
		run("Create Selection"); //makes all of the second channel into one big selection 
		run("Make Inverse");//need to invert it so when taking the intersection, we only take GFP+ NOT(Tph2)
		roiManager("Add"); //adds this selection as one ROI (at the end of the ROIs)
		for (i=0; i<(Ch1Num-1); i++){ //go up to the final ROI but don't assess because it's the combined Ch2 ROI
			roiManager("select", i);
			if((overlapArray[i]<colocThres)&&(overlapArray[i]>0)){
				roiManager("select",newArray(i,Ch1Num)); //select the Ch2 combined ROI
				roiManager("AND");
				roiManager("update");
			}
		}
		roiManager("deselect");
		roiManager("select",Ch1Num); //select the all Ch2 merged ROI
		roiManager("delete");
		roiManager("save", roiDir+"/"+saveName+"_Ch1_roi.zip"); //overwrite old ROIs
		File.makeDirectory(imageDir + "excludeOverlap/"); 
		overlapDir=imageDir + "excludeOverlap/";
		saveOverview(mask2,saveName, overlapDir, Ch2);
	}
	function overlapOverlay(mask, mask2, roiDir, cellindex, imageDir){
		/*
		 * This function generates an overlay for checking colocalization between mask and 
		 * mask2. This merges the two IHC channels and then overlays ROIs from one channel, then
		 * flattens, then overlays ROIs of the other channel and saves as a tiff to the 
		 * image dir. 
		 */
		 //duplicate and B&C adjust the two IHC channels
		selectWindow(mask);
		run("Duplicate...","title=ch1"); //never try to modify the original windows in case they need to be used later
		selectWindow("ch1");
		run("Enhance Contrast", "saturated=0.3");
		selectWindow(mask2);
		run("Duplicate...","title=ch2");
		run("Enhance Contrast", "saturated=0.3");
		//generate merged image
		run("Merge Channels...", "c2=ch1 c6=ch2 create keep ignore");
		//open up first set of ROIs and alter ROI manager display settings
		roiManager("reset");
		open(roiDir+saveName+"_Ch1_roi.zip");
		roiManager("Set Line Width", 3);
		roiManager("Set Color","orange");
		roiManager("Show All with labels");
		run("From ROI Manager");
		run("Labels...", "color=white font=15 show draw");
		//flatten to save bottom set of ROIs
		run("Flatten");
		//open second set of ROIs for Ch2 and alter ROI manager display settings
		open(roiDir+saveName+"_Ch2_roi.zip");
		roiManager("Select",cellindex);
		roiManager("Set Color","green");	
		roiManager("Set Line Width", 3);
		run("Labels...", "color=white font=15 show draw");
		run("From ROI Manager");
		//run("Labels...", "color=white font=24 show draw");
		saveAs(saveType,imageDir+saveName+"_colocOverlay.tiff");
		run("Close");
	}
	
	function removeColocCh2(roiDir,ch1CellNum,ch2CellNum,overlapArrayCh1,areaPercent, maxArea){
		/*This function opens rois contained in the roiDir path of Ch1 and Ch2, iterates over every combination of each Ch1
		 * object with the Ch2 object. When a match is found above the percent area colocalization threshold, this gathers 
		 * the index for the Ch2 object colocalized with the Ch1 object, prints this information to the log for the user, 
		 * and stores in deleteROIArray for later deletion of the data associated with that cell in Ch2 to avoid 
		 * confusion and doubling up on rows for colocalized cells in the final table. 
		 * OUTPUT: deleteROIArray
		 */
		deleteROIArray=newArray();
		roiManager("reset");
		open(roiDir+saveName+"_Ch1_roi.zip"); // primary channel, must be opened first
		open(roiDir+saveName+"_Ch2_roi.zip"); // secondary channel, less important
		//outer loop of Ch1 ROIs
		for (i=0; i<ch1CellNum; i++){
			run("Clear Results");
			if (overlapArrayCh1[i]>=areaPercent){
				roiManager("select", i); //select the Ch1 cell
				run("Measure");
				Ch1Area=getResult("Area",0); //always the first area because Results are cleared during each loop
				//inner loop of Ch2 ROIs
				for (j=ch1CellNum; j<(ch2CellNum+ch1CellNum); j++){
					roiManager("deselect");
					run("Clear Results");
					//measure the intersection area between the Ch1 and Ch2 cell pair
					roiManager("select", newArray(i,j));
					roiManager("AND");
					run("Measure");
					overlap=getResult("Area",0);
					//compare intersection to the areaPercent colocalization threshold
					if ((((overlap/Ch1Area)*100)>=areaPercent)&&(overlap<=Ch1Area)){
						deleteROIArray = Array.concat(deleteROIArray,j);
						print("cell "+(i+1)+" colocalized with cell "+(j+1)+", overlap: "+(overlap*100/Ch1Area)+"%");
					}
				}
			}
		}
		return deleteROIArray;
	}
	function deletePosition(indexArray, deletePos){
		/*
		 * This function takes an array indexArray, and deletes the entries with indices in deletePos.
		 * This is used to delete the indices corresponding to ROIs in Ch2 representing colocalized
		 * cells that are already present in the data table in Ch1.
		 * OUTPUT: array with positions deleted.
		 */
		//print("array before deletion");
		//Array.print(indexArray);
		for (i=0; i<lengthOf(deletePos); i++){
			position=deletePos[i];
			indexArray[position]=NaN;
		}
		indexArray=Array.delete(indexArray,NaN); //note will not work if there are already NaNs in the array fed into the function.
		//print("array after deletion");
		//Array.print(indexArray);
		return indexArray;
	}
	function getIntensity(roiDir, windowName,intensityArray){
		/*This function gets the intden of rois found within the roi dir (for GFP or ch1) in the channel indicated 
		 * by windowName and OUTPUTs a modified intensity array.
		 */
		 run("Clear Results");
		 roiManager("reset");
		 //open ROIs
		 open(roiDir+saveName+"_Ch1_roi.zip");
		 open(roiDir+saveName+"_Ch2_roi.zip");
		 numROIs=roiManager("count");
		 //measure and extract intden for each ROI and store in intensityArray
		 for(i=0;i<numROIs;i++){
		 	selectWindow(windowName);
		 	roiManager("select", i);
		 	run("Measure");
		 	//print(getResult("IntDen",i));
		 	intensityArray=Array.concat(intensityArray,getResult("IntDen",i));
		 	//Array.print(intensityArray);
		 }
		 return intensityArray;	 
	}
	function addToTable(array, title){
		/*This function is used to add a vector into a results table under the column name given by the title 
		 * variable. Note that the array should already be the appropriate length for the existing results table
		 * or you won't get what you want. 
		 */
		for(i=0;i<lengthOf(array);i++){
			setResult(title, i, array[i]);
		}
	}
	function punctaCount(saveName, roiDir, Ch, punctaChannel){
		/*
		 * This returns an array of puncta per ROI for a given punctaChannel and ROIS imported from an ROI directory
		 * Note that the set measurements have to be limited to threshold (include 'limit') for this to work properly
		 */
		run("Options...", "iterations=1 count=1 black do=Nothing");
		run("Clear Results");
		//open ROIs
		roiManager("reset");
		open(roiDir+saveName+"_Ch"+Ch+"_roi.zip");
		//isolate puncta with Find Maxima...
		selectWindow(punctaChannel);
		run("Duplicate...", "title=maxima");
		run("Find Maxima...", "prominence="+MP+" output=[Single Points]");
		run("Properties...", "channels=1 slices=1 frames=1 unit=pixel pixel_width=1.0000 pixel_height=1.0000 voxel_depth=1.0000"); //necessary to get area to be # pixels
		//select puncta
		run("Threshold...");
		setAutoThreshold("Default dark");
		roiManager("select all")
		//count puncta as area captured in each ROI in pixels
		roiManager("multi-measure measure_all");
		punctaArray=newArray(0);
		//append # of puncta per cell to array
		for (i=0; i<roiManager("count"); i++){
			punctaArray=Array.concat(punctaArray,getResult("Area",i));
		}
		//Array.print(punctaArray);
		return punctaArray;
	}
	function punctaOverlay(punctaChannel, mask, Ch1Index){
		/*
		 * This function takes in a puncta image name and a maxima image name and produces and saves an overlay image
		 * of the puncta and cell outlines over the image of puncta. Note that if no cell ROIs are present in the 
		 * manager, this won't add them. 
		 */
		//open ROIs
		roiManager("reset");
		open(roiDir+saveName+"_Ch1_roi.zip");
		open(roiDir+saveName+"_Ch2_roi.zip");
		//count puncta using Find Maxima...
		selectWindow(punctaChannel);
		run("Duplicate...","title=maxima_overlay");
		run("Find Maxima...", "prominence="+MP+" output=[Single Points]");
		rename("Maxima");
		//dilate them to be easier to see
		run("Dilate"); 
		//adjust B&C and label visuals
		selectWindow(punctaChannel);
		run("Enhance Contrast...", "saturated=0.3");
		run("Red");
		roiManager("Set Line Width", 2);
		roiManager("Set Color", "green");
		roiManager("select",Ch1Index);
		roiManager("Set Color", "orange");
		//put in ROIs from manager
		run("From ROI Manager");
		run("Labels...", "color=white font=24 show draw");//takes roimanager's settings for line color and width
		//flatten cell outlines onto image
		run("Flatten");
		rename("flat");
		//add in the maxima as an overlay so it can be toggled on and off
		selectWindow("Maxima");
		run("Create Selection");
		selectWindow("flat");
		run("Restore Selection");
		//adjust visuals of overlay
		run("Overlay Options...", "stroke=none width=0 fill=white");
		run("Add Selection...");
		run("Labels...", "color=white font=24 draw");
		run("Select None");
		close("Maxima");
		//save image
		rename(saveName+"_puncta_withCellOutlines");
		saveAs(saveType,imageDir+mask+"_puncta_withCellOutlines.tiff");
		/*Note, this function will save images as tiff files with overlays. The overlay can be toggled on and off in ImageJ.
		 * a helpful macro to assign the toggle to F1 is below. Copy and paste this onto the end of the Startup Macros file
		 * and restart imageJ to use: 
		 macro "Toggle Overlay [f1]" {
	      if (Overlay.size>0) {
	         if (Overlay.hidden)
	            Overlay.show;
	         else
	            Overlay.hide;
	      }
	   }
		 */
	}
	function closeIfOpen(string) {
		/*
		 * This function is useful if you desire to close a window by name but there is a chance depending on user action
		 * that the window may already be closed. 
		 */
	 	if (isOpen(string)) {
	         selectWindow(string);
	         run("Close");
	    }
	}
}
/*
 * For deleting ROIs easily, try installing this shortcut macro in the startup macros file
 * 
 * macro "Delete ROI [g]" {
	roiManager("delete");
}
 */