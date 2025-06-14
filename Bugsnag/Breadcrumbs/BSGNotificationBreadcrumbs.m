//
//  BSGNotificationBreadcrumbs.m
//  Bugsnag
//
//  Created by Nick Dowell on 10/12/2020.
//  Copyright © 2020 Bugsnag Inc. All rights reserved.
//

#import "BSGNotificationBreadcrumbs.h"

#import "BSGAppKit.h"
#import "BSGDefines.h"
#import "BSGKeys.h"
#import "BSGUIKit.h"
#import "BSGUtils.h"
#import "BugsnagBreadcrumbs.h"
#import "BugsnagConfiguration+Private.h"

BSG_OBJC_DIRECT_MEMBERS
@interface BSGNotificationBreadcrumbs ()

@property (nonatomic) NSDictionary<NSNotificationName, NSString *> *notificationNameMap;

@end

@interface BSGNotificationBreadcrumbs (/* not objc_direct */)

- (void)addBreadcrumbForNotification:(NSNotification *)notification;

- (void)addBreadcrumbForControlNotification:(NSNotification *)notification;

- (void)addBreadcrumbForMenuItemNotification:(NSNotification *)notification;

- (void)addBreadcrumbForTableViewNotification:(NSNotification *)notification;

#if TARGET_OS_IOS
- (void)orientationDidChange:(NSNotification *)notification;
#endif

- (void)thermalStateDidChange:(NSNotification *)notification API_AVAILABLE(ios(11.0), tvos(11.0));

@end


BSG_OBJC_DIRECT_MEMBERS
@implementation BSGNotificationBreadcrumbs

- (instancetype)initWithConfiguration:(BugsnagConfiguration *)configuration
                       breadcrumbSink:(id<BSGBreadcrumbSink>)breadcrumbSink {
    if ((self = [super init])) {
        _configuration = configuration;
        _notificationCenter = NSNotificationCenter.defaultCenter;
#if TARGET_OS_OSX
        _workspaceNotificationCenter = [NSWORKSPACE sharedWorkspace].notificationCenter;
#endif
        _breadcrumbSink = breadcrumbSink;
        _notificationNameMap = @{
            @"NSProcessInfoThermalStateDidChangeNotification" : @"Thermal State Changed", // Using string to avoid availability issues
            NSUndoManagerDidRedoChangeNotification : @"Redo Operation",
            NSUndoManagerDidUndoChangeNotification : @"Undo Operation",
#if TARGET_OS_TV
            UIScreenBrightnessDidChangeNotification : @"Screen Brightness Changed",
            UIWindowDidBecomeKeyNotification : @"Window Became Key",
            UIWindowDidResignKeyNotification : @"Window Resigned Key",
#elif TARGET_OS_IOS
            UIApplicationDidEnterBackgroundNotification : @"App Did Enter Background",
            UIApplicationDidReceiveMemoryWarningNotification : @"Memory Warning",
            UIApplicationUserDidTakeScreenshotNotification : @"Took Screenshot",
            UIApplicationWillEnterForegroundNotification : @"App Will Enter Foreground",
            UIApplicationWillTerminateNotification : BSGNotificationBreadcrumbsMessageAppWillTerminate,
            UIDeviceBatteryLevelDidChangeNotification : @"Battery Level Changed",
            UIDeviceBatteryStateDidChangeNotification : @"Battery State Changed",
            UIDeviceOrientationDidChangeNotification : @"Orientation Changed",
            UIKeyboardDidHideNotification : @"Keyboard Became Hidden",
            UIKeyboardDidShowNotification : @"Keyboard Became Visible",
            UIMenuControllerDidHideMenuNotification : @"Did Hide Menu",
            UIMenuControllerDidShowMenuNotification : @"Did Show Menu",
            UITextFieldTextDidBeginEditingNotification : @"Began Editing Text",
            UITextFieldTextDidEndEditingNotification : @"Stopped Editing Text",
            UITextViewTextDidBeginEditingNotification : @"Began Editing Text",
            UITextViewTextDidEndEditingNotification : @"Stopped Editing Text",
#elif TARGET_OS_OSX
            NSApplicationDidBecomeActiveNotification : @"App Became Active",
            NSApplicationDidHideNotification : @"App Did Hide",
            NSApplicationDidResignActiveNotification : @"App Resigned Active",
            NSApplicationDidUnhideNotification : @"App Did Unhide",
            NSApplicationWillTerminateNotification : BSGNotificationBreadcrumbsMessageAppWillTerminate,
            NSControlTextDidBeginEditingNotification : @"Control Text Began Edit",
            NSControlTextDidEndEditingNotification : @"Control Text Ended Edit",
            NSMenuWillSendActionNotification : @"Menu Will Send Action",
            NSTableViewSelectionDidChangeNotification : @"TableView Select Change",
            NSWindowDidBecomeKeyNotification : @"Window Became Key",
            NSWindowDidEnterFullScreenNotification : @"Window Entered Full Screen",
            NSWindowDidExitFullScreenNotification : @"Window Exited Full Screen",
            NSWindowWillCloseNotification : @"Window Will Close",
            NSWindowWillMiniaturizeNotification : @"Window Will Miniaturize",
            NSWorkspaceScreensDidSleepNotification : @"Workspace Screen Slept",
            NSWorkspaceScreensDidWakeNotification : @"Workspace Screen Awoke",
#endif
#if TARGET_OS_IOS || TARGET_OS_TV
            UISceneWillConnectNotification : @"Scene Will Connect",
            UISceneDidDisconnectNotification : @"Scene Disconnected",
            UISceneDidActivateNotification : @"Scene Activated",
            UISceneWillDeactivateNotification : @"Scene Will Deactivate",
            UISceneWillEnterForegroundNotification : @"Scene Will Enter Foreground",
            UISceneDidEnterBackgroundNotification : @"Scene Entered Background",
            UITableViewSelectionDidChangeNotification : @"TableView Select Change",
            UIWindowDidBecomeHiddenNotification : @"Window Became Hidden",
            UIWindowDidBecomeVisibleNotification : @"Window Became Visible",
#endif
        };
    }
    return self;
}

#if TARGET_OS_OSX
- (NSArray<NSNotificationName> *)workspaceBreadcrumbStateEvents {
    return @[
        NSWorkspaceScreensDidSleepNotification,
        NSWorkspaceScreensDidWakeNotification
    ];
}
#endif

- (NSArray<NSNotificationName> *)automaticBreadcrumbStateEvents {
    return @[
        NSUndoManagerDidRedoChangeNotification,
        NSUndoManagerDidUndoChangeNotification,
#if TARGET_OS_TV
        UIScreenBrightnessDidChangeNotification,
        UIWindowDidBecomeKeyNotification,
        UIWindowDidResignKeyNotification,
#elif TARGET_OS_IOS
        UIApplicationDidEnterBackgroundNotification,
        UIApplicationDidReceiveMemoryWarningNotification,
        UIApplicationUserDidTakeScreenshotNotification,
        UIApplicationWillEnterForegroundNotification,
        UIApplicationWillTerminateNotification,
        UIKeyboardDidHideNotification,
        UIKeyboardDidShowNotification,
        UIMenuControllerDidHideMenuNotification,
        UIMenuControllerDidShowMenuNotification,
#elif TARGET_OS_OSX
        NSApplicationDidBecomeActiveNotification,
        NSApplicationDidResignActiveNotification,
        NSApplicationDidHideNotification,
        NSApplicationDidUnhideNotification,
        NSApplicationWillTerminateNotification,
        
        NSWindowDidBecomeKeyNotification,
        NSWindowDidEnterFullScreenNotification,
        NSWindowDidExitFullScreenNotification,
        NSWindowWillCloseNotification,
        NSWindowWillMiniaturizeNotification,
#endif
#if TARGET_OS_IOS || TARGET_OS_TV
        UISceneWillConnectNotification,
        UISceneDidDisconnectNotification,
        UISceneDidActivateNotification,
        UISceneWillDeactivateNotification,
        UISceneWillEnterForegroundNotification,
        UISceneDidEnterBackgroundNotification,
        UIWindowDidBecomeHiddenNotification,
        UIWindowDidBecomeVisibleNotification,
#endif
    ];
}

- (NSArray<NSNotificationName> *)automaticBreadcrumbControlEvents {
#if TARGET_OS_IOS
    return @[
        UITextFieldTextDidBeginEditingNotification,
        UITextFieldTextDidEndEditingNotification,
        UITextViewTextDidBeginEditingNotification,
        UITextViewTextDidEndEditingNotification
    ];
#elif TARGET_OS_OSX
    return @[
        NSControlTextDidBeginEditingNotification,
        NSControlTextDidEndEditingNotification
    ];
#else
    return nil;
#endif
}

- (NSArray<NSNotificationName> *)automaticBreadcrumbTableItemEvents {
#if TARGET_OS_IOS || TARGET_OS_TV
    return @[UITableViewSelectionDidChangeNotification];
#elif TARGET_OS_OSX
    return @[NSTableViewSelectionDidChangeNotification];
#else
    return @[];
#endif
}

- (NSArray<NSNotificationName> *)automaticBreadcrumbMenuItemEvents {
#if TARGET_OS_OSX
    return @[ NSMenuWillSendActionNotification ];
#endif
    return nil;
}

- (void)dealloc {
    [_notificationCenter removeObserver:self];
}

#pragma mark -

- (NSString *)messageForNotificationName:(NSNotificationName)name {
    return self.notificationNameMap[name] ?: [name stringByReplacingOccurrencesOfString:@"Notification" withString:@""];
}

- (void)addBreadcrumbWithType:(BSGBreadcrumbType)type forNotificationName:(NSNotificationName)notificationName {
    [self addBreadcrumbWithType:type forNotificationName:notificationName metadata:nil];
}

- (void)addBreadcrumbWithType:(BSGBreadcrumbType)type forNotificationName:(NSNotificationName)notificationName metadata:(NSDictionary *)metadata {
    [self.breadcrumbSink leaveBreadcrumbWithMessage:[self messageForNotificationName:notificationName] metadata:metadata ?: @{} andType:type];
}

#pragma mark -

- (void)start {
    // State events
    if ([self.configuration shouldRecordBreadcrumbType:BSGBreadcrumbTypeState]) {
        // Generic state events
        for (NSNotificationName name in [self automaticBreadcrumbStateEvents]) {
            [self startListeningForStateChangeNotification:name];
        }
        
#if TARGET_OS_OSX
        // Workspace-specific events - macOS only
        for (NSNotificationName name in [self workspaceBreadcrumbStateEvents]) {
            [self.workspaceNotificationCenter addObserver:self
                                             selector:@selector(addBreadcrumbForNotification:)
                                                 name:name
                                               object:nil];
        }
        
        // NSMenu events (macOS only)
        for (NSNotificationName name in [self automaticBreadcrumbMenuItemEvents]) {
            [self.notificationCenter addObserver:self
                                    selector:@selector(addBreadcrumbForMenuItemNotification:)
                                        name:name
                                      object:nil];
        }
#endif
        
#if TARGET_OS_IOS
        [self.notificationCenter addObserver:self
                                    selector:@selector(orientationDidChange:)
                                        name:UIDeviceOrientationDidChangeNotification
                                      object:nil];
#endif
        
        if (@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)) {
            [self.notificationCenter addObserver:self
                                        selector:@selector(thermalStateDidChange:)
                                            name:NSProcessInfoThermalStateDidChangeNotification
                                          object:nil];
        }
    }
    
    // Navigation events
    if ([self.configuration shouldRecordBreadcrumbType:BSGBreadcrumbTypeNavigation]) {
        // UI/NSTableView events
        for (NSNotificationName name in [self automaticBreadcrumbTableItemEvents]) {
            [self.notificationCenter addObserver:self
                                    selector:@selector(addBreadcrumbForTableViewNotification:)
                                        name:name
                                      object:nil];
        }
    }
    
    // User events
    if ([self.configuration shouldRecordBreadcrumbType:BSGBreadcrumbTypeUser]) {
        // UITextField/NSControl events (text editing)
        for (NSNotificationName name in [self automaticBreadcrumbControlEvents]) {
            [self.notificationCenter addObserver:self
                                    selector:@selector(addBreadcrumbForControlNotification:)
                                        name:name
                                      object:nil];
        }
    }
}

- (void)startListeningForStateChangeNotification:(NSNotificationName)notificationName {
    [self.notificationCenter addObserver:self selector:@selector(addBreadcrumbForNotification:) name:notificationName object:nil];
}

- (BOOL)tryAddSceneNotification:(NSNotification *)notification {
#if (TARGET_OS_IOS && defined(__IPHONE_13_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0) || \
    (TARGET_OS_TV && defined(__TVOS_13_0) && __TV_OS_VERSION_MAX_ALLOWED >= __TVOS_13_0)
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        if ([notification.name hasPrefix:@"UIScene"] && [notification.object isKindOfClass:UISCENE]) {
            UIScene *scene = notification.object;
            NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
            metadata[@"configuration"] = scene.session.configuration.name;
            metadata[@"delegateClass"] = BSGStringFromClass(scene.session.configuration.delegateClass);
            metadata[@"role"] = scene.session.role;
            metadata[@"sceneClass"] = BSGStringFromClass(scene.session.configuration.sceneClass);
            metadata[@"title"] = scene.title.length ? scene.title : nil;
            [self addBreadcrumbWithType:BSGBreadcrumbTypeState forNotificationName:notification.name metadata:metadata];
            return YES;
        }
    }
#else
    (void)notification;
#endif
    return NO;
}

#if !TARGET_OS_WATCH
static NSString *nullStringIfBlank(NSString *str) {
    return str.length == 0 ? nil : str;
}
#endif

- (BOOL)tryAddWindowNotification:(NSNotification *)notification {
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
    if ([notification.name hasPrefix:@"UIWindow"] && [notification.object isKindOfClass:UIWINDOW]) {
        UIWindow *window = notification.object;
        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
        metadata[@"description"] = nullStringIfBlank(window.description);
#if TARGET_OS_IOS && defined(__IPHONE_13_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = window.windowScene;
            metadata[@"sceneTitle"] = nullStringIfBlank(scene.title);
#if defined(__IPHONE_15_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_15_0
            if (@available(iOS 15.0, *)) {
                metadata[@"sceneSubtitle"] = nullStringIfBlank(scene.subtitle);
            }
#endif
        }
#endif
        metadata[@"viewController"] = nullStringIfBlank(window.rootViewController.description);
        metadata[@"viewControllerTitle"] = nullStringIfBlank(window.rootViewController.title);
        [self addBreadcrumbWithType:BSGBreadcrumbTypeState forNotificationName:notification.name metadata:metadata];
        return YES;
    }
#endif

#if TARGET_OS_OSX
    if ([notification.name hasPrefix:@"NSWindow"] && [notification.object isKindOfClass:NSWINDOW]) {
        NSWindow *window = notification.object;
        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
        metadata[@"description"] = nullStringIfBlank(window.description);
        metadata[@"title"] = nullStringIfBlank(window.title);
#if defined(__MAC_11_0) && __MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_11_0
        if (@available(macOS 11.0, *)) {
            metadata[@"subtitle"] = nullStringIfBlank(window.subtitle);
        }
#endif
        metadata[@"representedURL"] = nullStringIfBlank(window.representedURL.absoluteString);
        metadata[@"viewController"] = nullStringIfBlank(window.contentViewController.description);
        metadata[@"viewControllerTitle"] = nullStringIfBlank(window.contentViewController.title);
        [self addBreadcrumbWithType:BSGBreadcrumbTypeState forNotificationName:notification.name metadata:metadata];
        return YES;
    }
#endif

    return NO;
}

- (void)addBreadcrumbForNotification:(NSNotification *)notification {
    if ([self tryAddSceneNotification:notification]) {
        return;
    }
    if ([self tryAddWindowNotification:notification]) {
        return;
    }
    [self addBreadcrumbWithType:BSGBreadcrumbTypeState forNotificationName:notification.name];
}

- (void)addBreadcrumbForTableViewNotification:(__unused NSNotification *)notification {
#if TARGET_OS_IOS || TARGET_OS_TV
    NSIndexPath *indexPath = ((UITableView *)notification.object).indexPathForSelectedRow;
    [self addBreadcrumbWithType:BSGBreadcrumbTypeNavigation forNotificationName:notification.name metadata:
     indexPath ? @{@"row" : @(indexPath.row), @"section" : @(indexPath.section)} : nil];
#elif TARGET_OS_OSX
    NSTableView *tableView = notification.object;
    [self addBreadcrumbWithType:BSGBreadcrumbTypeNavigation forNotificationName:notification.name metadata:
     tableView ? @{@"selectedRow" : @(tableView.selectedRow), @"selectedColumn" : @(tableView.selectedColumn)} : nil];
#endif
}

- (void)addBreadcrumbForMenuItemNotification:(__unused NSNotification *)notification {
#if TARGET_OS_OSX
    NSMenuItem *menuItem = [[notification userInfo] valueForKey:@"MenuItem"];
    [self addBreadcrumbWithType:BSGBreadcrumbTypeState forNotificationName:notification.name metadata:
     [menuItem isKindOfClass:NSMENUITEM] ? @{BSGKeyAction : menuItem.title} : nil];
#endif
}

- (void)addBreadcrumbForControlNotification:(__unused NSNotification *)notification {
#if TARGET_OS_IOS
    NSString *label = ((UIControl *)notification.object).accessibilityLabel;
    [self addBreadcrumbWithType:BSGBreadcrumbTypeUser forNotificationName:notification.name metadata:
     label.length ? @{BSGKeyLabel : label} : nil];
#elif TARGET_OS_OSX
    NSControl *control = notification.object;
    NSMutableDictionary *dict = NSMutableDictionary.new;
    if ([control respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *label = control.accessibilityLabel;
        if (label.length > 0) {
            [dict setObject:label forKey:BSGKeyLabel];
        }
    }
    [dict setObject:NSStringFromClass(control.class) forKey:@"controlClass"];
    NSUserInterfaceItemIdentifier identifier = control.identifier;
    if (identifier) {
      [dict setObject:identifier forKey:@"controlIdentifier"];
    }
    [self addBreadcrumbWithType:BSGBreadcrumbTypeUser forNotificationName:notification.name metadata:dict];
#endif
}

#pragma mark -

#if TARGET_OS_IOS

- (void)orientationDidChange:(NSNotification *)notification {
    UIDevice *device = notification.object;
    
    static UIDeviceOrientation previousOrientation;
    if (device.orientation == UIDeviceOrientationUnknown ||
        device.orientation == previousOrientation) {
        return;
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"from"] = BSGStringFromDeviceOrientation(previousOrientation);
    metadata[@"to"] =  BSGStringFromDeviceOrientation(device.orientation);
    previousOrientation = device.orientation;
    
    [self addBreadcrumbWithType:BSGBreadcrumbTypeState
            forNotificationName:notification.name
                       metadata:metadata];
}

#endif

- (void)thermalStateDidChange:(NSNotification *)notification API_AVAILABLE(ios(11.0), tvos(11.0)) {
    NSProcessInfo *processInfo = notification.object;
    
    static NSProcessInfoThermalState previousThermalState;
    if (processInfo.thermalState == previousThermalState) {
        return;
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"from"] = BSGStringFromThermalState(previousThermalState);
    metadata[@"to"] = BSGStringFromThermalState(processInfo.thermalState);
    previousThermalState = processInfo.thermalState;
    
    [self addBreadcrumbWithType:BSGBreadcrumbTypeState
            forNotificationName:notification.name
                       metadata:metadata];
}

@end
