//
//  BSGFileLocations.h
//  Bugsnag
//
//  Created by Karl Stenerud on 05.01.21.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "BSGDefines.h"

NS_ASSUME_NONNULL_BEGIN

BSG_OBJC_DIRECT_MEMBERS
@interface BSGFileLocations : NSObject

@property (readonly, nonatomic) NSString *breadcrumbs;
@property (readonly, nonatomic) NSString *events;
@property (readonly, nonatomic) NSString *kscrashReports;
@property (readonly, nonatomic) NSString *sessions;
@property (readonly, nonatomic) NSString *featureFlags;

/**
 Absolute path to lock file.
 - Note: Added by Sketch.
 */
@property (readonly, nonatomic) NSString *lockFile;

/**
 * File containing details of the current app hang (if the app is hung)
 */
@property (readonly, nonatomic) NSString *appHangEvent;

/**
 * File whose presence indicates that the libary at least attempted to handle the last
 * crash (in case it crashed before writing enough information).
 */
@property (readonly, nonatomic) NSString *flagHandledCrash;

/**
 * Bugsnag client configuration
 */
@property (readonly, nonatomic) NSString *configuration;

/**
 * General per-launch metadata
 */
@property (readonly, nonatomic) NSString *metadata;
/**
 * BSGRunContext
 */
@property (readonly, nonatomic) NSString *runContext;

/**
 * State info that gets added to the low level crash report.
 */
@property (readonly, nonatomic) NSString *state;

/**
 * State information about the app and operating envronment.
 */
@property (readonly, nonatomic) NSString *systemState;

/**
 * Persistent device ID shared with bugsnag-performance.
 */
@property (readonly, nonatomic) NSString *persistentDeviceID;

/**
 * Returns `YES` if the receiver uses an exclusive subdirectory, `NO` if it uses the shared default directory.
 *
 * - Note: Added by Sketch.
 */
@property (readonly, nonatomic) BOOL usesExclusiveSubdirectory;
/**
 Initialize the file locations.
 @param subdirectory If nil, use the regular shared directory. Else use the subdirectory with the given name, inside the `exclusiveDirectoryContainer`.

 @note: Added by Sketch.
 */
- (instancetype) initWithSubdirectory:(NSString * _Nullable)subdirectory;

/**
 Get the singleton, initializing it with the given subdirectory. Note that it is an error to call this multiple times with differing values.

 - Note: Added by Sketch.
 */
+ (instancetype) currentWithSubdirectory:(NSString * _Nullable)subdirectory;

/**
 Get the singleton. If not yet initialized, initializes it with a `nil` subdirectory.
 */
+ (instancetype) current;

+ (instancetype) v1;

/**
 Get the parent directory of the exclusive subdirectories.
 */
+ (NSString *)exclusiveDirectoryContainer;

/**
 Uses a `flock` to get exclusive ownership to write to this directory. This method blocks until it succeeds taking the lock.
 If any error occurs in the process, returns `NO` immediately.
 */
- (BOOL)lockForWritingBlocking;

/**
 Attempts to take a `flock` to get exclusive ownership to process to this directory. This method does *not* block.
 @return If locking succeeds, returns an NSFileHandle to the lock file, `nil` otherwise. To save resources, the handle should
 be closed once processing has finished.
 */
- (nullable NSFileHandle *)tryLockForProcessing;
@end

NS_ASSUME_NONNULL_END
