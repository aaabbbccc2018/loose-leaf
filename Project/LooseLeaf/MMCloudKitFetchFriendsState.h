//
//  MMCloudKitLoggedInState.h
//  LooseLeaf
//
//  Created by Adam Wulf on 8/25/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMCloudKitBaseState.h"
#import <SimpleCloudKitManager/SPRSimpleCloudKitManager.h>

@interface MMCloudKitFetchFriendsState : MMCloudKitBaseState

-(id) initWithUserRecord:(CKRecordID*)userRecord andUserInfo:(CKDiscoveredUserInfo*) userInfo;

@end
