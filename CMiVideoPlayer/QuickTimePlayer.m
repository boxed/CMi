//
//  QuickTimePlayer.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-02.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "QuickTimePlayer.h"

@implementation QuickTimePlayer

#pragma mark VideoPlayerProtocol

@synthesize movie;
@synthesize movieView;

- (id)initWithParentWindow:(NSWindow*)window
{
    self = [super initWithFrame:[[window contentView] frame]];
    if (self) {
        NSRect r = [[window contentView] frame];
        movieView = [[QTMovieView alloc] initWithFrame:r];
        [self setAutoresizingMask:NSViewHeightSizable|NSViewWidthSizable];
        [movieView setAutoresizingMask:NSViewHeightSizable|NSViewWidthSizable];
        //[window.contentView addSubview:self];
        //[self addSubview:movieView];
        [window.contentView addSubview:movieView];
        [movieView setHidden:TRUE];
    }
    
    return self;
}

- (void)openURL:(NSURL*)url
{
    NSError* error = nil;
    QTMovie *newMovie = [QTMovie movieWithURL:url error:&error];
    if (newMovie) {
        if (self.movie) {
            [self.movie stop];
        }
        [self setMovie:newMovie];
    }
    NSValue* v = (NSValue*)[newMovie attributeForKey:QTMovieNaturalSizeAttribute];
    [v getValue:&self->originalSize];
    [self play];
}

- (void)play
{
    [self->movie play];
}

- (void)pause
{
    // TODO: implement
}

- (void)stop
{
    [self->movie stop];    
}

- (void)setVolume:(float)volume
{
    [self->movie setVolume:volume];
}

- (void)setCurrentTime:(float)t
{
    QTTime time = QTMakeTimeWithTimeInterval(t);
    [self->movie setCurrentTime:time];
}

- (void)stepForward
{
    [self->movie stepForward];
}

- (void)stepBackward
{
    [self->movie stepBackward];
}

- (float)volume
{
    return [self->movie volume];
}

- (float)currentTime
{
    QTTime t = [self->movie currentTime];
    return t.timeValue;
}

- (float)duration
{
    NSTimeInterval duration;	
    QTGetTimeInterval([self.movie duration], &duration);
    return duration;
}

#pragma mark NSView
- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
    [self->movieView setBounds:self.bounds];
}

- (void)setHidden:(BOOL)hidden
{
    [movieView setHidden:hidden];
    [super setHidden:hidden];
    NSRect foo = self.bounds;
    foo.size.width /= 2;
    [self->movieView setBounds:self.bounds];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath* bp = [NSBezierPath bezierPathWithRect:dirtyRect];
    [[NSColor blueColor] setFill];
    [bp fill];
}

@end
