//
//  BorderLessWindow.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-13.
//  Copyright 2011 Hovmöller. See LICENSE file for license.
//

#import "BorderLessWindow.h"
#import "CMiVideoPlayerAppDelegate.h"

@implementation BorderLessWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

- (void)noResponderFor:(SEL)eventSelector
{
    // silence beeps
}


- (void)keyDown:(NSEvent *)theEvent
{
    [(CMiVideoPlayerAppDelegate*)self.delegate keyDown:theEvent];
}

@end
