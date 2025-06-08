//
//  MarkUnhandledHandledScenario.m
//  iOSTestApp
//
//  Created by Karl Stenerud on 03.12.20.
//  Copyright © 2020 Bugsnag. All rights reserved.
//

#import "MarkUnhandledHandledScenario.h"
#import "Logging.h"

@implementation MarkUnhandledHandledScenario

- (void)configure {
    [super configure];
    self.config.onCrashHandler = markErrorHandledCallback;
}

@end
