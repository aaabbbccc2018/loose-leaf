//
//  MMExportablePaperView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/28/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMExportablePaperView.h"
#import "NSFileManager+DirectoryOptimizations.h"
#import <ZipArchive/ZipArchive.h>


@implementation MMExportablePaperView{
    BOOL isCurrentlyExporting;
    BOOL isCurrentlySaving;
    BOOL waitingForExport;
    BOOL waitingForSave;
}


-(void) saveToDisk{
    @synchronized(self){
        if(isCurrentlySaving || isCurrentlyExporting){
            waitingForSave = YES;
            return;
        }
        isCurrentlySaving = YES;
        waitingForSave = NO;
    }
    [super saveToDisk];
}

-(void) saveToDisk:(void (^)(BOOL))onComplete{
    [super saveToDisk:^(BOOL hadEditsToSave){
        @synchronized(self){
            isCurrentlySaving = NO;
            [self retrySaveOrExport];
        }
        if(onComplete) onComplete(hadEditsToSave);
    }];
}

-(void) retrySaveOrExport{
    if(waitingForSave){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self saveToDisk];
        });
    }else if(waitingForExport){
        [self exportAsynchronouslyToZipFile];
    }
}

-(void) exportAsynchronouslyToZipFile{
    @synchronized(self){
        if(isCurrentlySaving || isCurrentlyExporting){
            waitingForExport = YES;
            return;
        }
        isCurrentlyExporting = YES;
        waitingForExport = NO;
    }
    
    dispatch_async([self serialBackgroundQueue], ^{
        NSString* generatedZipFile = [self generateZipFile];
        
        @synchronized(self){
            isCurrentlyExporting = NO;
            [self.delegate didExportPage:self toZipLocation:generatedZipFile];
            [self retrySaveOrExport];
        }
    });
}



-(NSString*) generateZipFile{
    
    NSString* pathOfPageFiles = [self pagesPath];
    
    NSUInteger hash1 = self.paperState.lastSavedUndoHash;
    NSUInteger hash2 = self.scrapsOnPaperState.lastSavedUndoHash;
    NSString* zipFileName = [NSString stringWithFormat:@"%@%lu%lu.zip", self.uuid, (unsigned long)hash1, (unsigned long)hash2];
    
    NSString* tempZipFileName = [zipFileName stringByAppendingPathExtension:@"temp"];
    
    // make sure temp file is deleted
    [[NSFileManager defaultManager] removeItemAtPath:tempZipFileName error:nil];
    
    NSArray * directoryContents = [[NSFileManager defaultManager] recursiveContentsOfDirectoryAtPath:pathOfPageFiles filesOnly:YES];
    
    NSString* fullPathToZip = [NSTemporaryDirectory() stringByAppendingPathComponent:tempZipFileName];
    
    ZipArchive* zip = [[ZipArchive alloc] init];
    if([zip createZipFileAt:fullPathToZip])
    {
        for(int filesSoFar=0;filesSoFar<[directoryContents count];filesSoFar++){
            NSString* aFileInPage = [directoryContents objectAtIndex:filesSoFar];
            if([zip addFileToZip:[pathOfPageFiles stringByAppendingPathComponent:aFileInPage]
                     toPathInZip:[self.uuid stringByAppendingPathComponent:aFileInPage]]){
            }else{
                NSLog(@"error for path: %@", aFileInPage);
            }
            CGFloat percentSoFar = ((CGFloat)filesSoFar / [directoryContents count]);
            [self.delegate isExportingPage:self withPercentage:percentSoFar toZipLocation:fullPathToZip];
        }
        [zip closeZipFile];
    }
    
    NSLog(@"success? %d", [[NSFileManager defaultManager] fileExistsAtPath:fullPathToZip]);
    
    NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPathToZip error:nil];
    if (attribs) {
        NSLog(@"zip file is %@", [NSByteCountFormatter stringFromByteCount:[attribs fileSize] countStyle:NSByteCountFormatterCountStyleFile]);
    }
    

    NSLog(@"validating zip file");
    zip = [[ZipArchive alloc] init];
    [zip unzipOpenFile:fullPathToZip];
    NSArray* contents = [zip contentsOfZipFile];
    [zip unzipCloseFile];
    
    if([contents count] == [directoryContents count]){
        NSLog(@"valid zip file");
        [[NSFileManager defaultManager] moveItemAtPath:tempZipFileName toPath:zipFileName error:nil];
    }else{
        NSLog(@"invalid zip file: %@ vs %@", contents, directoryContents);
    }
    
    /*
    
    NSLog(@"contents of zip: %@", contents);
    
    
    
    NSLog(@"unzipping file");
    
    NSString* unzipTargetDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safeDir"];
    
    zip = [[ZipArchive alloc] init];
    [zip unzipOpenFile:fullPathToZip];
    [zip unzipFileTo:unzipTargetDirectory overWrite:YES];
    [zip unzipCloseFile];
    
    
    directoryContents = [[NSFileManager defaultManager] recursiveContentsOfDirectoryAtPath:unzipTargetDirectory filesOnly:YES];
    NSLog(@"unzipped: %@", directoryContents);
    */
    
    return fullPathToZip;
}


@end
