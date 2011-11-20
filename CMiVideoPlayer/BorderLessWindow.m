//
//  BorderLessWindow.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-13.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "BorderLessWindow.h"


@implementation BorderLessWindow


- (void)hideCursor:(id)sender
{
    if (hideCount == 4)
    {
        CGDisplayHideCursor(kCGDirectMainDisplay);
        [self.delegate hideOnScreenControls];

    }
    else if (hideCount < 4)
    {
        hideCount++;
    }
}

- (void)initTimer
{
    hideCount = 4; // show the button a little while but fade it away almost directly
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(hideCursor:) userInfo:nil repeats:YES];
}

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

- (void)mouseMoved:(NSEvent *)theEvent
{
    hideCount = 0;
    CGDisplayShowCursor(kCGDirectMainDisplay);
    [super mouseMoved:theEvent];
    [self.delegate showOnScreenControls];
}

- (void)keyDown:(NSEvent *)theEvent
{
    [self.delegate keyDown:theEvent];
}

@end
