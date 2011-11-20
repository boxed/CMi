//
//  VLCVideoPlayer.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-09.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "VLCVideoPlayer.h"

@implementation VLCVideoPlayer

- (id)initWithParentWindow:(NSWindow*)inWindow
{
    self = [super init];
    if (self) {
        self->window = inWindow;
    }
    
    return self;
}

- (void)setHidden:(BOOL)b
{
    [self->view setHidden:b];
}

- (void)lazyInit
{
    if (view == nil) {
        view = [[VLCVideoView alloc] initWithFrame:[[window contentView] bounds]];
        player = [[VLCMediaPlayer alloc] initWithVideoView:view];
        [[window contentView] addSubview:view positioned:NSWindowBelow relativeTo:nil];
        [view setAutoresizingMask: NSViewHeightSizable|NSViewWidthSizable];
    }
}

- (void)openURL:(NSURL*)url
{
    [self lazyInit];
    [player setMedia:[VLCMedia mediaWithPath:[url path]]];
    [player play];
    isPaused = NO;
}

- (void)play
{
    [player play];
}

- (void)pause
{
    [player pause];
}

- (void)stop
{
    [player stop];
}

- (void)setVolume:(float)volume
{
    [[player audio] setVolume:(NSUInteger)(volume*100.0)];
}
     
- (void)setCurrentTime:(float)time
{
    VLCTime* vlctime = [VLCTime timeWithInt:(int)time];
    [player setTime:vlctime];
}

- (void)stepForward
{
    [player jumpForward:30];
}

- (void)stepBackward
{
    [player jumpBackward:30];
}

- (float)volume
{
    float f = (float)[[player audio] volume];
    return f/100.0;
}

- (float)currentTime
{
    VLCTime* time = [player time];
    return (float)[time intValue];
}

- (float)duration
{
    VLCTime* total = [[player media] length];
    return (float)[total intValue];
}

#pragma mark NSView
/*- (void)drawRect:(NSRect)dirtyRect
{
   if ([self hasVideo]) {
        [super drawRect:dirtyRect];
    }
    else {
        NSBezierPath* bp = [NSBezierPath bezierPathWithRect:dirtyRect];
        [[NSColor blueColor] setFill];
        [bp fill];
    }
}*/

@end
