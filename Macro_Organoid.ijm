/*
Plugins to install : 
IJPB
CLIJ/CLIJ2

This macro aims to quantify the organoid size and channel 2 intensity 

Macro author R. De Mets
Version : 0.2.0 , 7/8/2025
Otsu threshold
float connected components
ask for channels to segment
add CLIJ to filter based on circularity (https://forum.image.sc/t/excluding-masks-of-a-certain-circularity-before-converting-to-rois/76220/2) 
fix measurement channel error
add batch mode
add radio buttons for BF or Fluo image to segment organoid
works on tif and tiff
*/


// GUI and initialization
setBatchMode(false);
run("Close All");
print("\\Clear");
Dialog.create("GUI");
Dialog.addDirectory("Source image path","");
Dialog.addNumber("Which channels to identify organoids ?", 1);
Dialog.addRadioButtonGroup("", newArray("Fluorescent", "Brightfield"),1, 2, "Fluorescent");
Dialog.addCheckbox("Batch mode ? (no display, faster)", true);
Dialog.addNumber("Which channels is measure intensities ?", 2);
Dialog.addNumber("Minimum circularity ?", 0.85);
Dialog.addNumber("Minimum organoid size (px) ?", 500);
Dialog.show();

dirS = Dialog.getString;


folders = getFileList(dirS);
channel_BF = Dialog.getNumber();
modalities = Dialog.getRadioButton();
batch = Dialog.getCheckbox();
channel_Fluo = Dialog.getNumber();


minCircularity = Dialog.getNumber();
maxCircularity = 1.1;
minOrgSize = Dialog.getNumber();


if (batch) {
	setBatchMode(true);
}

for (i = 0; i < folders.length; i++) {
	if (matches(folders[i],".*/")) {
		filenames = getFileList(dirS+folders[i]);
		for (j = 0; j < filenames.length; j++) {
			currFile = dirS+folders[i]+filenames[j];
			print(currFile);
			if(endsWith(currFile, ".tiff") || endsWith(currFile, ".tif")) { // process tiff files matching regex
				//open(currFile);
				run("Clear Results");
				roiManager("reset");
				run("Bio-Formats Windowless Importer", "open=[" + currFile+"]");
				window_title = getTitle();
				getDimensions(width, height, channels, slices, frames);
				getPixelSize(unit, pw, ph, pd);
				title = File.nameWithoutExtension;
				
				
				// Background correction on the BF channel
				rename("raw");
				run("Split Channels");
				
				
				// Organoid identification
				
				if (modalities=="Brightfield") {
					//print("Brightfield image");
					selectWindow("C"+channel_BF+"-raw");
					run("Duplicate...", "title=blurred");
					
					selectWindow("blurred");
					run("Gaussian Blur...", "sigma=50");
					
					imageCalculator("Divide create 32-bit", "C"+channel_BF+"-raw","blurred");
					selectImage("Result of C"+channel_BF+"-raw");
					rename("corrected");
	
					// remove wells borders
					run("Median...", "radius=15");
					
					// Auto threshold default seems to work fine for most images.
					setAutoThreshold("Otsu");
					//run("Threshold...");
				}
				else {
					//print("Fluorescent image");
					selectWindow("C"+channel_BF+"-raw");
					run("Duplicate...", "title=blurred");
					run("Median...", "radius=3");
					setAutoThreshold("Otsu dark");
				}
				
				
				
				run("Create Selection");
				run("Create Mask");
				run("Fill Holes");
				run("Connected Components Labeling", "connectivity=8 type=[float]");

				
				// Test filter circularity
				labelmap = getTitle();

				//Measure shape features using MorpholibJ, add an entry for the background label (required for CLIJ)
				run("Analyze Regions", "circularity");
				circularity_CLIJ = Table.getColumn("Circularity");
				circularity_CLIJ = Array.concat(newArray(1), circularity_CLIJ);	//Insert a value (0) for the background label 0
				
				//init GPU
				run("CLIJ2 Macro Extensions", "cl_device=");
				Ext.CLIJ2_clear();

				
				//Push the labelmap image to the GPU, create a new filtered labelmap, and pull from GPU
				Ext.CLIJ2_push(labelmap);
				Ext.CLIJ2_pushArray(circularityVector, circularity_CLIJ, circularity_CLIJ.length, 1, 1);
				Ext.CLIJ2_excludeLabelsWithValuesOutOfRange(circularityVector, labelmap, labelmap_filtered, minCircularity, maxCircularity);
				Ext.CLIJ2_pull(labelmap_filtered);
				rename(labelmap+"_filtered");
			
				run("Label Size Filtering", "operation=Greater_Than size="+minOrgSize);
				// End test
				
				rename("Labels");
				
				// remove organoids at the border and save in ROI manager
				run("Remove Border Labels", "left right top bottom");
				setThreshold(1, 65535, "raw");
				run("Create Selection");
				roiManager("Add");
				roiManager("Save", dirS+folders[i]+title+"_roi.roi");
				roiManager("reset");
				
				run("Glasbey_on_dark");
				saveAs("Tiff", dirS+folders[i]+title+"_labels.tif");
				rename("Labels-killBorders");
				
				selectWindow("Mask-lbl-Morphometry");
				run("Close");
				
				// Analyse shape
				run("Analyze Regions", "area perimeter circularity");
				Area = Table.getColumn("Area");
				Perimeter = Table.getColumn("Perimeter");
				Circularity = Table.getColumn("Circularity");
				
				// Analyse intensities
				run("Intensity Measurements 2D/3D", "input=C"+channel_Fluo+"-raw labels=Labels-killBorders mean stddev min median numberofvoxels volume");
				rename("Results");
				
				
				// Fuse tables
				Table.setColumn("Area", Area);
				Table.setColumn("Perimeter", Perimeter);
				Table.setColumn("Circularity", Circularity);
				saveAs("Results", dirS+folders[i]+title+"_results.csv");
				run("Close All");
				close("*.csv");

				
			}
		}
	}
}


Dialog.create("Done");
Dialog.show();