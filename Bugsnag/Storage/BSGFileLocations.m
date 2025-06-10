//
//  BSGFileLocations.m
//  Bugsnag
//
//  Created by Karl Stenerud on 05.01.21.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import "BSGFileLocations.h"

#import "BSGInternalErrorReporter.h"
#import "BugsnagLogger.h"

/// - Note: Added by Sketch.
static NSString * const BSGExclusiveDirectoryContainerName = @"exclusiveDirectories";
/// - Note: Added by Sketch.
static NSString * const BSGLockFileName = @"lockFile";


static BOOL ensureDirExists(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if(![fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        bsg_log_err(@"Could not create directory %@: %@", path, error);
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [BSGInternalErrorReporter performBlock:^(BSGInternalErrorReporter *reporter) {
                [reporter reportErrorWithClass:@"Could not create directory"
                                       context:path.lastPathComponent
                                       message:BSGErrorDescription(error)
                                   diagnostics:error.userInfo];
            }];
        });
        return NO;
    }
    return YES;
}

static NSString *cachesDirectory(void) {
    // Default to an unusable location that will always fail.
    static NSString* rootPath = @"/";

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_TV
    // On tvOS, locations outside the caches directory are not writable, so fall back to using that.
    // https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html#//apple_ref/doc/uid/TP40015241
    NSSearchPathDirectory directory = NSCachesDirectory;
#else
    NSSearchPathDirectory directory = NSApplicationSupportDirectory;
#endif
        NSError *error = nil;
        NSURL *url = [NSFileManager.defaultManager URLForDirectory:directory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
        if (!url) {
            bsg_log_err(@"Could not locate directory for storage: %@", error);
            return;
        }


        rootPath = url.path;
    });


    return rootPath;
}

static NSString *bugsnagPath(NSString *fsVersion, NSString *subdirectory) {
    // Default to an unusable location that will always fail.
    static NSString* rootPath = @"/";

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (subdirectory != nil) {
            rootPath = [NSString stringWithFormat:@"%@/com.bugsnag.Bugsnag/%@/%@/%@/%@",
                        cachesDirectory(),
                        // Processes that don't have an Info.plist have no bundleIdentifier
                        NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName,
                        fsVersion, BSGExclusiveDirectoryContainerName, subdirectory];
        } else {
            rootPath = [NSString stringWithFormat:@"%@/com.bugsnag.Bugsnag/%@/%@",
                        cachesDirectory(),
                        // Processes that don't have an Info.plist have no bundleIdentifier
                        NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName,
                        fsVersion];
        }

        ensureDirExists(rootPath);
    });

    return rootPath;
}

static NSString *bugsnagSharedPath(void) {
    // Default to an unusable location that will always fail.
    static NSString* sharedPath = @"/";

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPath = [cachesDirectory() stringByAppendingFormat:@"/bugsnag-shared-%@",
                      [[NSBundle mainBundle] bundleIdentifier]];

        ensureDirExists(sharedPath);
    });

    return sharedPath;
}

static NSString *getAndCreateSubdir(NSString *rootPath, NSString *relativePath) {
    NSString *subdirPath = [rootPath stringByAppendingPathComponent:relativePath];
    ensureDirExists(subdirPath);
    return subdirPath;
}

BSG_OBJC_DIRECT_MEMBERS
@interface BSGFileLocations()
/// Name of the exclusive subdirectory used. Nil if the shared shared directory is used.
@property (nonatomic, copy, nullable) NSString *exclusiveSubdirectory;
@end

@implementation BSGFileLocations

static BSGFileLocations *current = nil;
static dispatch_once_t onceToken;

+ (instancetype)current {
    dispatch_once(&onceToken, ^{
        current = [BSGFileLocations v1WithSubdirectory:nil];
    });
    return current;
}

+ (instancetype)v1 {
    return [[BSGFileLocations alloc] initWithVersion1WithSubdirectory:nil];
}

+ (instancetype)currentWithSubdirectory:(NSString * _Nullable)subdirectory {
    dispatch_once(&onceToken, ^{
        current = [BSGFileLocations v1WithSubdirectory:subdirectory];
    });

    if (!(current.exclusiveSubdirectory == subdirectory || [current.exclusiveSubdirectory isEqual:subdirectory])) {
        bsg_log_err(@"WARNING: API violation. Attempting to initialize BSGFileLocations with non-matching subdirectories");
    }

    return current;
}

+ (instancetype)v1WithSubdirectory:(NSString * _Nullable)subdirectory {
    return [[BSGFileLocations alloc] initWithVersion1WithSubdirectory:subdirectory];
}

- (instancetype)initWithVersion1 {
    return [self initWithVersion1WithSubdirectory:nil];
}

- (instancetype)initWithSubdirectory:(NSString * _Nullable)subdirectory {
    return [self initWithVersion1WithSubdirectory:subdirectory];
}

- (instancetype)initWithVersion1WithSubdirectory:(NSString * _Nullable)subdirectory {
    if ((self = [super init])) {
        NSString *root = bugsnagPath(@"v1", subdirectory);
        _events = getAndCreateSubdir(root, @"events");
        _sessions = getAndCreateSubdir(root, @"sessions");
        _breadcrumbs = getAndCreateSubdir(root, @"breadcrumbs");
        _kscrashReports = getAndCreateSubdir(root, @"KSCrashReports");
        _featureFlags = getAndCreateSubdir(root, @"featureFlags");
        _appHangEvent = [root stringByAppendingPathComponent:@"app_hang.json"];
        _flagHandledCrash = [root stringByAppendingPathComponent:@"bugsnag_handled_crash.txt"];
        _configuration = [root stringByAppendingPathComponent:@"config.json"];
        _metadata = [root stringByAppendingPathComponent:@"metadata.json"];
        _runContext = [root stringByAppendingPathComponent:@"run_context"];
        _state = [root stringByAppendingPathComponent:@"state.json"];
        _systemState = [root stringByAppendingPathComponent:@"system_state.json"];
        // --- begin section added by Sketch
        _lockFile = [root stringByAppendingPathComponent:BSGLockFileName];
        _exclusiveSubdirectory = [subdirectory copy];
        // --- end section added by Sketch

        _persistentDeviceID = [bugsnagSharedPath() stringByAppendingPathComponent:@"device-id.json"];
    }
    return self;
}

+ (NSString *)exclusiveDirectoryContainer {
    return [self v1ExclusiveDirectoryContainer];
}

+ (NSString *)v1ExclusiveDirectoryContainer {
    NSString *root = bugsnagPath(@"v1", nil);
    return [root stringByAppendingPathComponent:BSGExclusiveDirectoryContainerName];
}

- (BOOL)lockForWritingBlocking {
    // Open and lock the lock file, creating it if it doesn't exist. Do block.
    int fd = open(self.lockFile.UTF8String, O_RDWR | O_CREAT | O_TRUNC | O_EXLOCK, S_IRUSR | S_IWUSR);

    if (fd < 0 ) {
        bsg_log_info(@"failed to lock for writing res: %i error: %s", fd, strerror(errno));
        return NO;
    }
    // NOTE: We currently "leak" the file descriptor here, since currently we don't ever want to unlock
    // until we quit.
    return YES;
}

- (nullable NSFileHandle *)tryLockForProcessing {
    // Open and lock the lock file. Fail if file does not exist. Do not block.
    int fd = open(self.lockFile.UTF8String, O_RDONLY | O_EXLOCK | O_NONBLOCK, S_IRUSR | S_IWUSR);

    if (fd < 0 ) {
        // We failed to lock, probably another process in writing to it right now.
        return nil;
    }

    return [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}

- (BOOL)usesExclusiveSubdirectory {
    return self.exclusiveSubdirectory != nil;
}

@end
