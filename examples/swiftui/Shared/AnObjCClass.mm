// Copyright (c) 2016 Bugsnag, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AnObjCClass.h"

#import <stdexcept>

@implementation AnObjCClass

- (void)trap {
    __builtin_trap();
}

- (void)corruptSomeMemory {
    /* Some random data */
    void *cache[] = {
        NULL, NULL, NULL
    };

    void *displayStrings[6] = {
        (void *)"This little piggy went to the meerket",
        (void *)"This little piggy stayed at home",
        cache,
        (void *)"This little piggy had roast beef.",
        (void *)"This little piggy had none.",
        (void *)"And this little piggy went 'Wee! Wee! Wee!' all the way home",
    };

    /* A corrupted/under-retained/re-used piece of memory */
    struct {
        void *isa;
    } corruptObj;
    corruptObj.isa = displayStrings;

    /* Message an invalid/corrupt object. This will deadlock crash reporters
     * using Objective-C. */
    [(__bridge id)&corruptObj class];
}

- (void)accessInvalidMemoryAddress {
    // This should result in an EXC_BAD_ACCESS mach exception with code = KERN_INVALID_ADDRESS and subcode = 0xDEADBEEF
    void (* ptr)(void) = (void (*)(void))0xDEADBEEF;
    ptr();
}

- (void)throwCxxException {
    throw std::runtime_error("This is a C++ exception");
}

@end
