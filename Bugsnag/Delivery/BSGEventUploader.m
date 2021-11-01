//
//  BSGEventUploader.m
//  Bugsnag
//
//  Created by Nick Dowell on 17/02/2021.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import "BSGEventUploader.h"

#import "BSGEventUploadKSCrashReportOperation.h"
#import "BSGEventUploadObjectOperation.h"
#import "BSGFileLocations.h"
#import "BSGJSONSerialization.h"
#import "BSGUtils.h"
#import "BugsnagConfiguration.h"
#import "BugsnagEvent+Private.h"
#import "BugsnagLogger.h"
#import "BugsnagNotifier.h"

@interface BSGEventUploader () <BSGEventUploadOperationDelegate>

@property (readonly, nonatomic) NSString *eventsDirectory;

@property (readonly, nonatomic) NSString *kscrashReportsDirectory;

@property (readonly, nonatomic) NSOperationQueue *scanQueue;

@property (readonly, nonatomic) NSOperationQueue *uploadQueue;

@end


// MARK: -

@implementation BSGEventUploader

@synthesize apiClient = _apiClient;
@synthesize configuration = _configuration;
@synthesize notifier = _notifier;

- (instancetype)initWithConfiguration:(BugsnagConfiguration *)configuration notifier:(BugsnagNotifier *)notifier {
    return [self initWithConfiguration:configuration eventsDirectory:[BSGFileLocations current].events crashReportsDirectory: [BSGFileLocations current].kscrashReports notifier:notifier];
}

- (instancetype)initWithConfiguration:(BugsnagConfiguration *)configuration eventsDirectory:(NSString *)eventsDirectory crashReportsDirectory:(NSString *)crashReportsDirectory notifier:(BugsnagNotifier *)notifier {
    self = [super init];
    if (self) {
        _apiClient = [[BugsnagApiClient alloc] initWithSession:configuration.session queueName:@""];
        _configuration = configuration;
        _eventsDirectory = eventsDirectory;
        _kscrashReportsDirectory = crashReportsDirectory;
        _notifier = notifier;
        _scanQueue = [[NSOperationQueue alloc] init];
        _scanQueue.maxConcurrentOperationCount = 1;
        _scanQueue.name = @"com.bugsnag.event-scanner";
        _uploadQueue = [[NSOperationQueue alloc] init];
        _uploadQueue.maxConcurrentOperationCount = 1;
        _uploadQueue.name = @"com.bugsnag.event-uploader";
    }
    return self;
}


- (void)dealloc {
    [_scanQueue cancelAllOperations];
    [_uploadQueue cancelAllOperations];
}

// MARK: - Public API

- (void)storeEvent:(BugsnagEvent *)event {
    [event symbolicateIfNeeded];
    [self storeEventPayload:[event toJsonWithRedactedKeys:self.configuration.redactedKeys]];
}

- (void)uploadEvent:(BugsnagEvent *)event completionHandler:(nullable void (^)(void))completionHandler {
    if (self.configuration.suppressNetworkOperations) {
        bsg_log_warn(@"asked to upload event even though suppressNetworkOperations == YES.");
    }

    NSUInteger operationCount = self.uploadQueue.operationCount;
    if (operationCount >= self.configuration.maxPersistedEvents) {
        bsg_log_warn(@"Dropping notification, %lu outstanding requests", (unsigned long)operationCount);
        if (completionHandler) {
            completionHandler();
        }
        return;
    }
    BSGEventUploadObjectOperation *operation = [[BSGEventUploadObjectOperation alloc] initWithEvent:event delegate:self];
    operation.completionBlock = completionHandler;
    [self.uploadQueue addOperation:operation];
}

+ (BOOL)synchronouslyUploadExclusiveReportsWithConfiguration:(BugsnagConfiguration *)configuration {

    BugsnagNotifier *notifier = [BugsnagNotifier new];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;

    NSString *container = [BSGFileLocations exclusiveDirectoryContainer];

    NSArray<NSString *> * contents = [fm contentsOfDirectoryAtPath:container error:&error];
    if (!contents) {
        // Log the error, except if it indicates that the directory is simply missing, since this can legitimately happen.
        if ([error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError) {
            return YES;
        }
        bsg_log_err(@"failed to get contents of exclusive container: %@", error);
        return NO;
    }

    BOOL success = YES;

    // Enumerate subdirectories.
    for (NSString *item in contents) {
        @autoreleasepool {
            NSString *fullItemPath = [container stringByAppendingPathComponent:item];
            BOOL isDirectory;
            if (![fm fileExistsAtPath:fullItemPath isDirectory:&isDirectory] || !isDirectory) {
                continue;
            }

            // Instantiate locations for this subdirectory.
            BSGFileLocations *locations = [[BSGFileLocations alloc] initWithSubdirectory:item];

            // Lock the directory. If locking fails, it might indicate that the writer is still writing to it.
            // In that case, we simply ignore it. A future upload should deal with the directory once the lock is released.
            NSFileHandle *processingLock = [locations tryLockForProcessing];
            if (!processingLock) {
                continue;
            }

            bsg_log_info(@"processing events in exclusive subdirectory %@", item);

            // We make a copy of the configuration which has the exclusive subdirectory set to our value.
            // At the time of writing, this is not strictly necessary, but seems cleaner.
            BugsnagConfiguration *subConfiguration = [configuration copy];
            subConfiguration.exclusiveSubdirectory = item;

            // Init an uploader for our subdirectory.
            BSGEventUploader *uploader = [[self alloc] initWithConfiguration:subConfiguration eventsDirectory:locations.events crashReportsDirectory:locations.kscrashReports notifier:notifier];

            // Upload any events.
            [uploader synchronouslyUploadEvents];

            // If we managed to upload all events successfully, we delete this subdirectory.
            if ([uploader sortedEventFiles].count == 0) {
                if (![fm removeItemAtPath:fullItemPath error:&error]) {
                    bsg_log_err(@"failed to delete exclusive event directory after upload: %@", error);
                    success = NO;
                }
            } else {
                // Most likely cause is that we failed to upload because of a network error.
                bsg_log_err(@"failed to process all events in subdirectory %@", item);
                success = NO;
            }
            [processingLock closeFile];
        }
    }
    return success;
}

- (void)uploadStoredEvents {
    if (self.configuration.suppressNetworkOperations) {
        bsg_log_warn(@"asked to upload stored events even though suppressNetworkOperations == YES.");
    }
    if (self.scanQueue.operationCount > 1) {
        // Prevent too many scan operations being scheduled
        return;
    }
    bsg_log_debug(@"Will scan stored events");
    [self.scanQueue addOperationWithBlock:^{
        NSMutableArray<NSString *> *sortedFiles = [self sortedEventFiles];
        [self deleteExcessFiles:sortedFiles];
        NSArray<BSGEventUploadFileOperation *> *operations = [self uploadOperationsWithFiles:sortedFiles];
        bsg_log_debug(@"Uploading %lu stored events", (unsigned long)operations.count);
        [self.uploadQueue addOperations:operations waitUntilFinished:NO];
    }];
}

- (void)uploadStoredEventsAfterDelay:(NSTimeInterval)delay {
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, ^{
        [self uploadStoredEvents];
    });
}

- (void)uploadLatestStoredEvent:(void (^)(void))completionHandler {
    if (self.configuration.suppressNetworkOperations) {
        bsg_log_warn(@"asked to upload latest stored event even though suppressNetworkOperations == YES.");
    }

    NSString *latestFile = [self sortedEventFiles].lastObject;
    BSGEventUploadFileOperation *operation = latestFile ? [self uploadOperationsWithFiles:@[latestFile]].lastObject : nil;
    if (!operation) {
        bsg_log_warn(@"Could not find a stored event to upload");
        completionHandler();
        return;
    }
    operation.completionBlock = completionHandler;
    [self.uploadQueue addOperation:operation];
}

- (void)synchronouslyUploadEvents {
    if (self.configuration.suppressNetworkOperations) {
        bsg_log_warn(@"asked to upload latest stored event even though suppressNetworkOperations == YES.");
    }
    NSArray<BSGEventUploadFileOperation *> *operations = [self uploadOperationsWithFiles:[self sortedEventFiles]];
    [self.uploadQueue addOperations:operations waitUntilFinished:YES];
}

// MARK: - Implementation

/// Returns the stored event files sorted from oldest to most recent.
- (NSMutableArray<NSString *> *)sortedEventFiles {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    
    NSMutableDictionary<NSString *, NSDate *> *creationDates = [NSMutableDictionary dictionary];
    
    for (NSString *directory in @[self.eventsDirectory, self.kscrashReportsDirectory]) {
        NSError *error = nil;
        NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:&error];
        if (!entries) {
            bsg_log_err(@"%@", error);
            continue;
        }
        
        for (NSString *filename in entries) {
            if (![filename.pathExtension isEqual:@"json"] || [filename hasSuffix:@"-CrashState.json"]) {
                continue;
            }
            
            NSString *file = [directory stringByAppendingPathComponent:filename];
            NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
            creationDates[file] = attributes.fileCreationDate;
            [files addObject:file];
        }
    }
    
    [files sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        NSDate *rhsDate = creationDates[rhs];
        if (!rhsDate) {
            return NSOrderedDescending;
        }
        return [creationDates[lhs] compare:rhsDate];
    }];
    
    return files;
}

/// Deletes the oldest files until no more than `config.maxPersistedEvents` remain and removes them from the array.
- (void)deleteExcessFiles:(NSMutableArray<NSString *> *)sortedEventFiles {
    while (sortedEventFiles.count > self.configuration.maxPersistedEvents) {
        NSString *file = sortedEventFiles[0];
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:file error:&error]) {
            bsg_log_debug(@"Deleted %@ to comply with maxPersistedEvents", file);
        } else {
            bsg_log_err(@"Error while deleting file: %@", error);
        }
        [sortedEventFiles removeObject:file];
    }
}

/// Creates an upload operation for each file that is not currently being uploaded
- (NSArray<BSGEventUploadFileOperation *> *)uploadOperationsWithFiles:(NSArray<NSString *> *)files {
    NSMutableArray<BSGEventUploadFileOperation *> *operations = [NSMutableArray array];
    
    NSMutableSet<NSString *> *currentFiles = [NSMutableSet set];
    for (id operation in self.uploadQueue.operations) {
        if ([operation isKindOfClass:[BSGEventUploadFileOperation class]]) {
            [currentFiles addObject:((BSGEventUploadFileOperation *)operation).file];
        }
    }
    
    for (NSString *file in files) {
        if ([currentFiles containsObject:file]) {
            continue;
        }
        NSString *directory = file.stringByDeletingLastPathComponent;
        if ([directory isEqualToString:self.kscrashReportsDirectory]) {
            [operations addObject:[[BSGEventUploadKSCrashReportOperation alloc] initWithFile:file delegate:self]];
        } else {
            [operations addObject:[[BSGEventUploadFileOperation alloc] initWithFile:file delegate:self]];
        }
    }
    
    return operations;
}

// MARK: - BSGEventUploadOperationDelegate

- (void)storeEventPayload:(NSDictionary *)eventPayload {
    dispatch_sync(BSGGetFileSystemQueue(), ^{
        NSString *file = [[self.eventsDirectory stringByAppendingPathComponent:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:@"json"];
        NSError *error = nil;
        if (![BSGJSONSerialization writeJSONObject:eventPayload toFile:file options:0 error:&error]) {
            bsg_log_err(@"Error encountered while saving event payload for retry: %@", error);
            return;
        }
        [self deleteExcessFiles:[self sortedEventFiles]];
    });
}

@end
