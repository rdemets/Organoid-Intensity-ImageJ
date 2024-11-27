


// This macro aims to quantify the organoid size and channel 2 intensity 
// All function used are available from the stable version of Fiji and PTBIOP plugins.


// Macro author R. De Mets
// Version : 0.1.4 , 11/09/2024
// Otsu threshold
// float connected components
//ask for channels to segment
// add CLIJ to filter based on circularity (https://forum.image.sc/t/excluding-masks-of-a-certain-circularity-before-converting-to-rois/76220/2) 


// GUI and initialization
setBatchMode(true);
run("Close All");
print("\\Clear");
Dialog.create("GUI");
Dialog.addDirectory("Source image path","");
Dialog.addNumber("Which channels is the BF channel ?", 2);
Dialog.addNumber("Which channels is the Fluo channel ?", 3);
Dialog.addNumber("Minimum circularity ?", 0.85);
Dialog.addNumber("Minimum organoid size (px) ?", 500);
Dialog.show();

dirS = Dialog.getString;


folders = getFileList(dirS);
channel_BF = Dialog.getNumber();
channel_Fluo = Dialog.getNumber();


minCircularity = Dialog.getNumber();
maxCircularity = 1.1;
minOrgSize = Dialog.getNumber();



for (i = 0; i < folders.length; i++) {
	if (matches(folders[i],".*/")) {
		filenames = getFileList(dirS+folders[i]);
		for (j = 0; j < filenames.length; j++) {
		// Open file if CZI
			currFile = dirS+folders[i]+filenames[j];
			print(currFile);
			if(endsWith(currFile, ".tiff")) { // process tiff files matching regex
				//open(currFile);
				run("Clear Results");
				roiManager("reset");
				run("Bio-Formats Windowless Importer", "open=[" + currFile+"]");
				window_title = getTitle();
				getDimensions(width, height, channels, slices, frames);
				getPixelSize(unit, pw, ph, pd);
				title = File.nameWithoutExtension;
				print(window_title);
				
				
				// Background correction on the last channel
				rename("raw");
				run("Split Channels");
				selectWindow("C"+channel_BF+"-raw");
				run("Duplicate...", " ");
				run("Gaussian Blur...", "sigma=50");
				rename("blurred");
				
				imageCalculator("Divide create 32-bit", "C"+channel_BF+"-raw","blurred");
				selectImage("Result of C"+channel_BF+"-raw");
				rename("corrected");

				
				// remove wells
				run("Median...", "radius=12");
				
				// Auto threshold default seems to work fine for most images.
				setAutoThreshold("Otsu");
				//run("Threshold...");
				run("Create Selection");
				run("Create Mask");
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
				run("Intensity Measurements 2D/3D", "input=C"+channels-1+"-raw labels=Labels-killBorders mean stddev min median numberofvoxels volume");
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