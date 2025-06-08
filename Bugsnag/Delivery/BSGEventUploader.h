//
//  BSGEventUploader.h
//  Bugsnag
//
//  Created by Nick Dowell on 16/02/2021.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "BSGDefines.h"

@class BugsnagApiClient;
@class BugsnagConfiguration;
@class BugsnagEvent;
@class BugsnagNotifier;

NS_ASSUME_NONNULL_BEGIN

BSG_OBJC_DIRECT_MEMBERS
@interface BSGEventUploader : NSObject

- (instancetype)initWithConfiguration:(BugsnagConfiguration *)configuration notifier:(BugsnagNotifier *)notifier;

- (void)storeEvent:(BugsnagEvent *)event;

- (void)uploadEvent:(BugsnagEvent *)event completionHandler:(nullable void (^)(void))completionHandler;

- (void)uploadKSCrashReportWithFile:(NSString *)file completionHandler:(nullable void (^)(void))completionHandler;

- (void)uploadStoredEvents;

- (void)uploadStoredEventsAfterDelay:(NSTimeInterval)delay;

- (void)uploadLatestStoredEvent:(void (^)(void))completionHandler;

/**
 *  Process all events found in any of the exclusive subdirectories. The directories are deleted after successful upload.
 *  This method ignores directories that are currently locked by the writer.
 *  @param configuration The configuration to use. This is mainly used for the API key and upload session.
 *  @returns YES if all crash reports were successfully processed, NO if there was any kind of problem.
 */
+ (BOOL)synchronouslyUploadExclusiveReportsWithConfiguration:(BugsnagConfiguration *)configuration;
@end

NS_ASSUME_NONNULL_END
