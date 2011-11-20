//
//  VolumeView.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-16.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "VolumeView.h"

@implementation VolumeView

- (void)drawRect:(NSRect)dirtyRect
{
    float volume = [[NSUserDefaults standardUserDefaults] floatForKey:@"volume"];;
    [[NSColor whiteColor] set];
    NSBezierPath* path = [NSBezierPath bezierPathWithRect:dirtyRect];
    [path setLineWidth:4];
    [path stroke];
    dirtyRect.size.height *= volume;
    dirtyRect = NSInsetRect(dirtyRect, 4, 4);
    [[NSBezierPath bezierPathWithRect:dirtyRect] fill];
}

@end
