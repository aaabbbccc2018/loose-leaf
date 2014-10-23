//
//  MMScrapsOnPaperState.m
//  LooseLeaf
//
//  Created by Adam Wulf on 9/26/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapsOnPaperState.h"
#import "MMScrapView.h"
#import "MMScrapViewState.h"
#import "MMImmutableScrapsOnPaperState.h"
#import "MMScrapContainerView.h"
#import "NSThread+BlockAdditions.h"
#import "UIView+Debug.h"
#import "Constants.h"
#import "MMPageCacheManager.h"
#import "MMScrapsInBezelContainerView.h"
#import "MMTrashManager.h"
#import <Crashlytics/Crashlytics.h>

@interface MMImmutableScrapsOnPaperState (Private)

-(NSUInteger) undoHash;

@end

/**
 * similar to the MMPaperState, this object will
 * track the state for all scraps within a single page
 */
@implementation MMScrapsOnPaperState{
    // the container to hold the scraps
    MMScrapContainerView* scrapContainerView;
}

@dynamic delegate;
@synthesize scrapContainerView;

-(id) initWithDelegate:(NSObject<MMScrapsOnPaperStateDelegate>*)_delegate withScrapContainerSize:(CGSize)scrapContainerSize{
    if(self = [super init]){
        delegate = _delegate;
        scrapContainerView = [[MMScrapContainerView alloc] initWithFrame:CGRectMake(0, 0, scrapContainerSize.width, scrapContainerSize.height)
                                                   forScrapsOnPaperState:self];
        // anchor the view to the top left,
        // so that when we scale down, the drawable view
        // stays in place
        scrapContainerView.layer.anchorPoint = CGPointMake(0,0);
        scrapContainerView.layer.position = CGPointMake(0,0);
    }
    return self;
}

-(int) fullByteSize{
    int totalBytes = 0;
    @synchronized(allLoadedScraps){
        for(MMScrapView* scrap in allLoadedScraps){
            totalBytes += scrap.fullByteSize;
        }
    }
    return totalBytes;
}

#pragma mark - Save and Load

-(void) loadStateAsynchronously:(BOOL)async atPath:(NSString*)scrapIDsPath andMakeEditable:(BOOL)makeEditable{
    if(self.isForgetful){
        return;
    }
    CheckThreadMatches([NSThread isMainThread] || [MMTrashManager isTrashManagerQueue]);
    if(![self isStateLoaded]){
        __block NSArray* scrapProps;
        __block NSArray* scrapIDsOnPage;
        BOOL wasAlreadyLoading = isLoading;
        @synchronized(self){
            isLoading = YES;
            if(makeEditable){
                targetLoadedState = MMScrapCollectionStateTargetLoadedEditable;
            }else if(targetLoadedState == MMScrapCollectionStateTargetUnloaded){
                // only set to loaded+notEditable if our current target is unloaded
                targetLoadedState = MMScrapCollectionStateTargetLoadedNotEditable;
            }
        }
        
        NSMutableArray* scrapPropsWithState = [NSMutableArray array];

        __block BOOL hasBailedOnLoadingBecauseOfMismatchedTargetState = NO;
        
        void (^blockForImportExportStateQueue)() = ^(void) {
            CheckThreadMatches([NSThread isMainThread] || [MMTrashManager isTrashManagerQueue] || [MMScrapCollectionState isImportExportStateQueue]);
            @autoreleasepool {
                if(self.isForgetful){
                    return;
                }
//#ifdef DEBUG
//                [NSThread sleepForTimeInterval:5];
//#endif
                @synchronized(self){
                    if(targetLoadedState == MMScrapCollectionStateTargetUnloaded){
                        NSLog(@"MMScrapsOnPaperState bailing early");
                        hasBailedOnLoadingBecauseOfMismatchedTargetState = YES;
                        return;
                    }
                }
                NSDictionary* allScrapStateInfo = [NSDictionary dictionaryWithContentsOfFile:scrapIDsPath];
                
                if([[NSFileManager defaultManager] fileExistsAtPath:scrapIDsPath] && !allScrapStateInfo){
                    NSLog(@"corruped file at %@", scrapIDsPath);
                }
                scrapIDsOnPage = [allScrapStateInfo objectForKey:@"scrapsOnPageIDs"];
                scrapProps = [allScrapStateInfo objectForKey:@"allScrapProperties"];
            }
        };
        void (^blockForMainThread)() = ^{
            @autoreleasepool {
                if(self.isForgetful){
                    return;
                }
                if([self isStateLoaded]){
                    // it's possible that we were asked to load asynchronously
                    // which would add this block to the main thread, then asked
                    // again to load synchronously, which would run before
                    // this block would've had the chance. so always
                    // double check if we've already loaded before we thought
                    // we needed to.
                    return;
                }
                if(hasBailedOnLoadingBecauseOfMismatchedTargetState){
                    NSLog(@"MMScrapsOnPaperState main thread bailing early");
                    isLoaded = NO;
                    isLoading = NO;
                    return;
                }
                // load all the states async
                if([scrapProps count]){
                    for(NSDictionary* scrapProperties in scrapProps){
                        if(self.isForgetful){
                            return;
                        }
                        @synchronized(self){
                            if(targetLoadedState == MMScrapCollectionStateTargetUnloaded){
                                hasBailedOnLoadingBecauseOfMismatchedTargetState = YES;
                                isLoaded = NO;
                                isLoading = NO;
                                return;
                            }
                        }
                        
                        NSString* scrapUUID = [scrapProperties objectForKey:@"uuid"];
                        
                        MMScrapView* scrap = [delegate scrapForUUIDIfAlreadyExistsInOtherContainer:scrapUUID];
                        
                        NSMutableDictionary* props = [NSMutableDictionary dictionaryWithDictionary:scrapProperties];
                        if(scrap && scrap.state.scrapsOnPaperState == self){
                            //                        NSLog(@"page found scrap on sidebar %@", scrapUUID);
                            [props setObject:scrap forKey:@"scrap"];
                            [scrapPropsWithState addObject:props];
                        }else{
                            __block MMScrapViewState* state = nil;
                            state = [[MMScrapViewState alloc] initWithUUID:scrapUUID andPaperState:self];
                            if(state){
                                [props setObject:state forKey:@"state"];
                                [scrapPropsWithState addObject:props];
                            }else{
                                // failed to load scrap
                                NSLog(@"failed to load %@ at %@", scrapUUID, scrapIDsPath);
                            }
                        }
                    }
                }
                
                // maintain order of loaded scraps, so that they are added to the page
                // in the correct order as they load
                [scrapPropsWithState sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                    return [scrapIDsOnPage indexOfObject:[obj1 objectForKey:@"uuid"]] < [scrapIDsOnPage indexOfObject:[obj2 objectForKey:@"uuid"]] ? NSOrderedAscending : NSOrderedDescending;
                }];
                for(NSDictionary* scrapProperties in scrapPropsWithState){
                    if(self.isForgetful){
                        return;
                    }
                    MMScrapView* scrap = nil;
                    if([scrapProperties objectForKey:@"scrap"]){
                        scrap = [scrapProperties objectForKey:@"scrap"];
                        //                            NSLog(@"page %@ reused scrap %@", delegate.uuid, scrap.uuid);
                    }else{
                        MMScrapViewState* scrapState = [scrapProperties objectForKey:@"state"];
                        scrap = [[MMScrapView alloc] initWithScrapViewState:scrapState];
                        //                            NSLog(@"page %@ built scrap %@", delegate.uuid, scrap.uuid);
                        // only set properties if we built the scrap,
                        // otherwise it's in the sidebar and we don't
                        // own it right now
                        [scrap setPropertiesDictionary:scrapProperties];
                    }
                    if(scrap){
                        @synchronized(allLoadedScraps){
                            [allLoadedScraps addObject:scrap];
                        }
                        
                        BOOL isShownOnPage = NO;
                        if([scrapIDsOnPage containsObject:scrap.uuid]){
                            [self.delegate didLoadScrapInContainer:scrap];
                            [self showScrap:scrap];
                            isShownOnPage = YES;
                        }else{
                            [self.delegate didLoadScrapOutOfContainer:scrap];
                        }
                        
                        if(isShownOnPage && makeEditable){
                            [scrap loadScrapStateAsynchronously:async];
                        }else{
                            [scrap unloadState];
                        }
                    }
                }
                @synchronized(self){
                    isLoaded = YES;
                    isLoading = NO;
                    MMImmutableScrapCollectionState* immutableState = [self immutableStateForPath:nil];
                    expectedUndoHash = [immutableState undoHash];
                    lastSavedUndoHash = [immutableState undoHash];
                    //                        NSLog(@"loaded scrapsOnPaperState at: %lu", (unsigned long)lastSavedUndoHash);
                }
                [self.delegate didLoadAllScrapsFor:self];
                
                // we were asked to unload halfway through loading,
                // so in case that unload already finished while we
                // were creating scraps, we should re-fire the unload
                // call, just in case
                @synchronized(self){
                    if(targetLoadedState == MMScrapCollectionStateTargetUnloaded){
                        NSLog(@"MMScrapsOnPaperState: loaded a scrapsOnPaperState, but was asked to unload it after all");
                        dispatch_async([MMScrapCollectionState importExportStateQueue], ^{
                            @autoreleasepool {
                                [self unloadPaperState];
                            }
                        });
                    }
                }
            }
        };
        
        if(!async){
            // this will load from the background thread synchronously
            // and then will run the main thread synchronously.
            // if already on the main thread, it won't block waiting
            // on itself
            blockForImportExportStateQueue();
            [NSThread performBlockOnMainThreadSync:blockForMainThread];
        }else if(wasAlreadyLoading){
            // noop, it's already loading asynchornously
            // so we don't need to do anything extra
        }else if(async){
            // we're not yet loading and we want to load
            // asynchronously
            //
            // this will load from disk on the background queue,
            // and then will add the block to the main thread
            // after that
            dispatch_async([MMScrapCollectionState importExportStateQueue], blockForImportExportStateQueue);
            dispatch_async([MMScrapCollectionState importExportStateQueue], ^{
                [NSThread performBlockOnMainThread:blockForMainThread];
            });
        }
    }else if([self isStateLoaded] && makeEditable){
        void (^loadScrapsForAlreadyLoadedState)() = ^(void) {
            @autoreleasepool {
                if([self isStateLoaded]){
                    for(MMScrapView* scrap in self.scrapsOnPaper){
                        [scrap loadScrapStateAsynchronously:async];
                    }
                }
                @synchronized(self){
                    if(targetLoadedState == MMScrapCollectionStateTargetUnloaded){
                        NSLog(@"MMScrapsOnPaperState: loaded a scrapsOnPaperState, but was asked to unload it after all");
                        dispatch_async([MMScrapCollectionState importExportStateQueue], ^{
                            @autoreleasepool {
                                [self unloadPaperState];
                            }
                        });
                    }
                }
            }
        };
        if(async){
            dispatch_async([MMScrapCollectionState importExportStateQueue], loadScrapsForAlreadyLoadedState);
        }else{
            // we're already on the correct thread, so just run it now
            loadScrapsForAlreadyLoadedState();
        }
    }
}

-(void) unloadPaperState{
    CheckThreadMatches([MMScrapCollectionState isImportExportStateQueue]);
    [super unloadPaperState];
}

-(MMImmutableScrapsOnPaperState*) immutableStateForPath:(NSString*)scrapIDsPath{
    if(scrapIDsPath){
        CheckThreadMatches([MMScrapCollectionState isImportExportStateQueue])
    }
    if([self isStateLoaded]){
        hasEditsToSave = NO;
        @synchronized(allLoadedScraps){
            MMImmutableScrapsOnPaperState* immutable = [[MMImmutableScrapsOnPaperState alloc] initWithScrapIDsPath:scrapIDsPath
                                                                                                      andAllScraps:allLoadedScraps
                                                                                                   andScrapsOnPage:self.scrapsOnPaper andOwnerState:self];
            expectedUndoHash = [immutable undoHash];
            return immutable;
        }
    }
    return nil;
}

-(void) performBlockForUnloadedScrapStateSynchronously:(void(^)())block onBlockComplete:(void(^)())onComplete andLoadFrom:(NSString*)scrapIDsPath withBundledScrapIDsPath:(NSString*)bundledScrapIDsPath andImmediatelyUnloadState:(BOOL)shouldImmediatelyUnload{
    CheckThreadMatches([NSThread isMainThread] || [MMTrashManager isTrashManagerQueue]);
    if([self isStateLoaded]){
        @throw [NSException exceptionWithName:@"LoadedStateForUnloadedBlockException"
                                       reason:@"Cannot run block on unloaded state when state is already loaded" userInfo:nil];
    }
    @autoreleasepool {
        //
        // the following loadState: call will run a portion of
        // its load synchronously on [MMScrapCollectionState importExportStateQueue]
        // which means that the importExportStateQueue will be effectively empty.
        //
        // this method is not allowed to be called from the importExportStateQueue
        // itself, so the load method below won't be run with pending blocks already
        // on the queue.
        if([[NSFileManager defaultManager] fileExistsAtPath:scrapIDsPath]){
            [self loadStateAsynchronously:NO atPath:scrapIDsPath andMakeEditable:YES];
        }else{
            [self loadStateAsynchronously:NO atPath:bundledScrapIDsPath andMakeEditable:YES];
        }
    }
    block();
    dispatch_async([MMScrapCollectionState importExportStateQueue], ^(void) {
        // the importExportStateQueue might be being used by another scrapsOnPaperState
        // to save itself to disk, so its not necessarily empty at this point. we
        // must call the onComplete asynchronously.
        @autoreleasepool {
            onComplete();
            if(shouldImmediatelyUnload){
                //
                // this will add the unload block to be the very next block to run
                // asynchrously from the currently empty importExportStateQueue queue
                dispatch_async([MMScrapCollectionState importExportStateQueue], ^(void) {
                    @autoreleasepool {
                        [self unloadPaperState];
                    }
                });
            }
        }
    });
}

#pragma mark - Create Scraps

-(MMScrapView*) addScrapWithPath:(UIBezierPath*)path andRotation:(CGFloat)rotation andScale:(CGFloat)scale{
    if(![self isStateLoaded]){
        @throw [NSException exceptionWithName:@"ModifyingUnloadedScrapsOnPaperStateException" reason:@"cannot add scrap to unloaded ScrapsOnPaperState" userInfo:nil];
    }
    MMScrapView* newScrap = [[MMScrapView alloc] initWithBezierPath:path andScale:scale andRotation:rotation andPaperState:self];
    @synchronized(allLoadedScraps){
        [allLoadedScraps addObject:newScrap];
    }
    return newScrap;
}

#pragma mark - Manage Scraps

-(NSArray*) scrapsOnPaper{
    // we'll be calling this method quite often,
    // so don't create a new auto-released array
    // all the time. instead, just return our subview
    // array, so that if the caller just needs count
    // or to iterate on the main thread, we don't
    // spend unnecessary resources copying a potentially
    // long array.
    @synchronized(scrapContainerView){
        return scrapContainerView.subviews;
    }
}

-(void) showScrap:(MMScrapView*)scrap atIndex:(NSUInteger)subviewIndex{
    [self showScrap:scrap];
    [scrap.superview insertSubview:scrap atIndex:subviewIndex];
}

-(void) showScrap:(MMScrapView*)scrap{
    CheckMainThread;
    if(!scrap.state.scrapsOnPaperState){
        // if the scrap doesn't have a paperstate,
        // then its loading while being deleted,
        // so just fail silently
        return;
    }
    if(scrap.state.scrapsOnPaperState != self){
        @throw [NSException exceptionWithName:@"ScrapAddedToWrongPageException" reason:@"This scrap was added to a page that doesn't own it" userInfo:nil];
    }
    @synchronized(scrapContainerView){
        [scrapContainerView addSubview:scrap];
    }
    [scrap setShouldShowShadow:self.delegate.isEditable];
    if(isLoaded || isLoading){
        [scrap loadScrapStateAsynchronously:YES];
    }else{
        [scrap unloadState];
    }
}

-(void) hideScrap:(MMScrapView*)scrap{
    @synchronized(scrapContainerView){
        if(scrapContainerView == scrap.superview){
            [scrap setShouldShowShadow:NO];
            [scrap removeFromSuperview];
        }else{
            @throw [NSException exceptionWithName:@"MMScrapContainerException" reason:@"Removing scrap from a container that doesn't own it" userInfo:nil];
        }
    }
}

-(BOOL) isScrapVisible:(MMScrapView*)scrap{
    return [self.scrapsOnPaper containsObject:scrap];
}

-(void) scrapVisibilityWasUpdated:(MMScrapView*)scrap{
    if([self isStateLoaded] && !isLoading && !isUnloading){
        // something changed w/ scrap visibility
        // we only care if we're fully loaded, not if
        // we're loading or unloading.
        hasEditsToSave = YES;
    }
}

-(MMScrapView*) mostRecentScrap{
    @synchronized(allLoadedScraps){
        return [allLoadedScraps lastObject];
    }
}


#pragma mark - Saving Helpers

-(MMScrapView*) removeScrapWithUUID:(NSString*)scrapUUID{
    @synchronized(allLoadedScraps){
        MMScrapView* removedScrap = nil;
        NSMutableArray* otherArray = [NSMutableArray array];
        for(MMScrapView* scrap in allLoadedScraps){
            if(![scrap.uuid isEqualToString:scrapUUID]){
                [otherArray addObject:scrap];
            }else{
                removedScrap = scrap;
                [NSThread performBlockOnMainThreadSync:^{
                    [removedScrap removeFromSuperview];
                }];
//                NSLog(@"permanently removed scrap %@ from page %@", scrapUUID, self.delegate.uuidOfScrapCollectionStateOwner);
            }
        }
        allLoadedScraps = otherArray;
        hasEditsToSave = YES;
        return removedScrap;
    }
}

#pragma mark - Paths

-(NSString*) directoryPathForScrapUUID:(NSString*)uuid{
    NSString* scrapPath = [[self.delegate.pagesPath stringByAppendingPathComponent:@"Scraps"] stringByAppendingPathComponent:uuid];
    return scrapPath;
}

-(NSString*) bundledDirectoryPathForScrapUUID:(NSString*)uuid{
    NSString* scrapPath = [[self.delegate.bundledPagesPath stringByAppendingPathComponent:@"Scraps"] stringByAppendingPathComponent:uuid];
    return scrapPath;
}

#pragma mark - Deleting Assets

-(void) deleteScrapWithUUID:(NSString*)scrapUUID shouldRespectOthers:(BOOL)respectOthers{
    // for scrapsOnPaperState, we need to ask
    // the page to delete the scrap, as we don't
    // own all of the assets for it
    [self.delegate deleteScrapWithUUID:scrapUUID shouldRespectOthers:respectOthers];
}

@end
