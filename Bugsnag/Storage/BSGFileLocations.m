//
//  BSGFileLocations.m
//  Bugsnag
//
//  Created by Karl Stenerud on 05.01.21.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import "BSGFileLocations.h"
#import "BugsnagLogger.h"

static NSString * const BSGAtomicDirectoryContainerName = @"atomic";
static NSString * const BSGLockFileName = @"lockFile";

static BOOL ensureDirExists(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if(![fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        bsg_log_err(@"Could not create directory %@: %@", path, error);
        return NO;
    }
    return YES;
}

static NSString *rootDirectory(NSString *fsVersion, NSString *subdirectory) {
    // Default to an unusable location that will always fail.
    static NSString* defaultRootPath = @"/";
    static NSString* rootPath = @"/";
    
#if TARGET_OS_TV
    // On tvOS, locations outside the caches directory are not writable, so fall back to using that.
    // https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html#//apple_ref/doc/uid/TP40015241
    NSSearchPathDirectory directory = NSCachesDirectory;
#else
    NSSearchPathDirectory directory = NSApplicationSupportDirectory;
#endif
    NSError *error = nil;
    NSURL *url = [NSFileManager.defaultManager URLForDirectory:directory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    if (!url) {
        bsg_log_err(@"Could not locate directory for storage: %@", error);
        return rootPath;
    }
    
    if (subdirectory != nil) {
        rootPath = [NSString stringWithFormat:@"%@/com.bugsnag.Bugsnag/%@/%@/%@/%@",
                    url.path,
                    // Processes that don't have an Info.plist have no bundleIdentifier
                    NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName,
                    fsVersion, BSGAtomicDirectoryContainerName, subdirectory];
    } else {
        rootPath = [NSString stringWithFormat:@"%@/com.bugsnag.Bugsnag/%@/%@",
                    url.path,
                    // Processes that don't have an Info.plist have no bundleIdentifier
                    NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName,
                    fsVersion];
    }
    
    // If we can't even create the root dir, all is lost, and no file ops can be allowed.
    if (!ensureDirExists(rootPath)) {
        rootPath = defaultRootPath;
    }
    
    return rootPath;
}

static NSString *getAndCreateSubdir(NSString *rootPath, NSString *relativePath) {
    NSString *subdirPath = [rootPath stringByAppendingPathComponent:relativePath];
    if (ensureDirExists(subdirPath)) {
        return subdirPath;
    }
    // Make the best of it, just return the root dir.
    return rootPath;
}

@interface BSGFileLocations()
/// Name of the atomic subdirectory used. Nil if the shared shared directory is used.
@property (nonatomic, copy, nullable) NSString *atomicSubdirectory;
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

    if (!(current.atomicSubdirectory != subdirectory || ![current.atomicSubdirectory isEqual:subdirectory])) {
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
    self = [super init];
    if (self) {
        NSString *root = rootDirectory(@"v1", subdirectory);
        _events = getAndCreateSubdir(root, @"events");
        _sessions = getAndCreateSubdir(root, @"sessions");
        _breadcrumbs = getAndCreateSubdir(root, @"breadcrumbs");
        _kscrashReports = getAndCreateSubdir(root, @"KSCrashReports");
        _kvStore = getAndCreateSubdir(root, @"kvstore");
        _appHangEvent = [root stringByAppendingPathComponent:@"app_hang.json"];
        _flagHandledCrash = [root stringByAppendingPathComponent:@"bugsnag_handled_crash.txt"];
        _configuration = [root stringByAppendingPathComponent:@"config.json"];
        _metadata = [root stringByAppendingPathComponent:@"metadata.json"];
        _state = [root stringByAppendingPathComponent:@"state.json"];
        _systemState = [root stringByAppendingPathComponent:@"system_state.json"];
        _lockFile = [root stringByAppendingPathComponent:BSGLockFileName];
        _atomicSubdirectory = [subdirectory copy];
    }
    return self;
}

+ (NSString *)atomicDirectoryContainer {
    return [self v1AtomicDirectoryContainer];
}

+ (NSString *)v1AtomicDirectoryContainer {
    NSString *root = rootDirectory(@"v1", nil);
    return [root stringByAppendingPathComponent:BSGAtomicDirectoryContainerName];
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

- (BOOL)tryLockForProcessing {
    // Open and lock the lock file. Fail if file does not exist. Do not block.
    int fd = open(self.lockFile.UTF8String, O_RDONLY | O_EXLOCK | O_NONBLOCK, S_IRUSR | S_IWUSR);

    if (fd < 0 ) {
        bsg_log_info(@"failed to lock for processing res: %i error: %s", fd, strerror(errno));
        return NO;
    }

    // NOTE: We currently "leak" the file descriptor here, since currently we don't ever want to unlock
    // until we quit.
    return YES;
}

- (BOOL)usesAtomicSubdirectory {
    return self.atomicSubdirectory != nil;
}

@end
