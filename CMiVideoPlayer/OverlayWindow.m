//
//  OverlayWindow.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-30.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "OverlayWindow.h"
#import "CMiVideoPlayerAppDelegate.h"
@implementation OverlayWindow

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)awakeFromNib
{
    [self setOpaque:NO];
    [self setBackgroundColor:[NSColor clearColor]];
    [self setAlphaValue:0.5];
    [self setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
}

- (void)keyDown:(NSEvent *)theEvent
{
    [(CMiVideoPlayerAppDelegate*)self.delegate keyDown:theEvent];
}
@end
