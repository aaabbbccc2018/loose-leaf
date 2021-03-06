//
//  MMPanAndPinchScrapGestureRecognizer.h
//  LooseLeaf
//
//  Created by Adam Wulf on 8/25/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Constants.h"
#import "MMScrapView.h"
#import "MMPanAndPinchScrapGestureRecognizerDelegate.h"
#import "MMVector.h"
#import "MMCancelableGestureRecognizer.h"
#import "MMUndoablePaperView.h"


@interface MMPanAndPinchScrapGestureRecognizer : MMCancelableGestureRecognizer <UIGestureRecognizerDelegate> {
    // the initial distance between
    // the touches. to be used to calculate
    // scale
    CGFloat initialDistance;

    // the collection of valid touches for this gesture
    NSMutableSet* ignoredTouches;
    NSMutableOrderedSet* possibleTouches;
    NSMutableOrderedSet* validTouches;

    // track which bezels our delegate cares about
    MMBezelDirection bezelDirectionMask;
    // the direction that the user actually did exit, if any
    MMBezelDirection didExitToBezel;
    // track the direction of the scale
    MMBezelScaleDirection scaleDirection;

    //
    // don't allow both the 2nd to last touch
    // and the last touch to trigger a repeat
    // of the bezel
    BOOL secondToLastTouchDidBezel;

    __weak NSObject<MMPanAndPinchScrapGestureRecognizerDelegate>* scrapDelegate;

    // will hold the original page that the scrap was on
    // before it was panned
    __weak MMUndoablePaperView* startingPageForScrap;
}

@property (nonatomic, assign) BOOL shouldReset;
@property (nonatomic, assign) MMBezelDirection bezelDirectionMask;
@property (nonatomic, readonly) MMBezelDirection didExitToBezel;
@property (nonatomic, weak) NSObject<MMPanAndPinchScrapGestureRecognizerDelegate>* scrapDelegate;
@property (readonly) NSArray* validTouches;
@property (nonatomic, readonly) CGFloat scale;
@property (nonatomic, readonly) CGFloat rotation;
@property (nonatomic, readonly) CGPoint translation;
@property (nonatomic, readonly) BOOL isShaking;
@property (nonatomic, weak) MMScrapView* scrap;
@property (assign) CGFloat preGestureScale;
@property (assign) CGFloat preGesturePageScale;
@property (assign) CGFloat preGestureRotation;
@property (assign) CGPoint preGestureCenter;
@property (readonly) MMVector* initialTouchVector;
@property (nonatomic, readonly) NSDictionary* startingScrapProperties;
@property (nonatomic, readonly) MMUndoablePaperView* startingPageForScrap;

- (void)ownershipOfTouches:(NSSet*)touches isGesture:(UIGestureRecognizer*)gesture;
- (void)relinquishOwnershipOfTouches:(NSSet*)touches;
- (void)giveUpScrap;
- (void)blessTouches:(NSSet*)touches;
- (void)forceBlessTouches:(NSSet*)touches forScrap:(MMScrapView*)_scrap;

- (NSArray*)possibleTouches;
- (NSArray*)ignoredTouches;


- (BOOL)paused;
- (void)pause;
- (BOOL)begin;

@end
