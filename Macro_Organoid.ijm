


// This macro aims to quantify the organoid size and channel 2 intensity 
// All function used are available from the stable version of Fiji and PTBIOP plugins.


// Macro author R. De Mets
// Version : 0.1.1 , 16/08/2024


// GUI and initialization
setBatchMode(true);
run("Close All");
print("\\Clear");
Dialog.create("GUI");
Dialog.addDirectory("Source image path","");
Dialog.show();

dirS = Dialog.getString;

folders = getFileList(dirS);
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
				selectWindow("C"+channels+"-raw");
				run("Duplicate...", " ");
				run("Gaussian Blur...", "sigma=30");
				rename("blurred");
				
				imageCalculator("Divide create 32-bit", "C"+channels+"-raw","blurred");
				selectImage("Result of C"+channels+"-raw");
				rename("corrected");
				
				
				// remove wells
				run("Median...", "radius=10");
				
				// Auto threshold default seems to work fine for most images.
				setAutoThreshold("Default");
				//run("Threshold...");
				run("Create Selection");
				run("Create Mask");
				run("Connected Components Labeling", "connectivity=8 type=[16 bits]");
				rename("Labels");
				
				// remove organoids at the border and save in ROI manager
				run("Remove Border Labels", "left right top bottom");
				setThreshold(1, 65535, "raw");
				run("Create Selection");
				roiManager("Add");
				roiManager("Save", dirS+folders[i]+title+"_roi.roi");
				roiManager("reset");
				
				saveAs("Tiff", dirS+folders[i]+title+"_labels.tif");
				rename("Labels-killBorders");
				
				
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