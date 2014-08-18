//
//  MMShareManagerDelegate.h
//  LooseLeaf
//
//  Created by Adam Wulf on 8/13/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol MMShareManagerDelegate <NSObject>

-(void) allCellsWillLoad;

-(void) cellLoaded:(UIView*)cell forIndexPath:(NSIndexPath*)indexPath;

-(void) allCellsLoaded:(NSArray*)arrayOfAllLoadedButtonIndexes;

-(void) sharingHasEnded;

-(void) isSendingToApplication:(NSString *)application;

@end