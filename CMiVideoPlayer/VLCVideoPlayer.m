//
//  VLCVideoPlayer.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-09.
//  Copyright 2011 Hovmöller. See LICENSE file for license.
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
        player.delegate = self;
        [[window contentView] addSubview:view positioned:NSWindowBelow relativeTo:nil];
        [view setAutoresizingMask: NSViewHeightSizable|NSViewWidthSizable];
    }
}

- (void)openURL:(NSURL*)url
{
    [self lazyInit];
    self->prevState = VLCMediaPlayerStateOpening;
    if ([url isFileURL]) {
        [player setMedia:[VLCMedia mediaWithPath:[url path]]];
    }
    else {
        [player setMedia:[VLCMedia mediaWithURL:url]];
    }
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
    if ((int)time == 0) {
        vlctime = [VLCTime nullTime];
    }
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

#pragma mark VLCMediaPlayerDelegate
- (void)mediaPlayerStateChanged:(NSNotification *)aNotification
{
    if (self->prevState != self->player.state && self->player.state == VLCMediaPlayerStatePlaying) {
        player.currentVideoSubTitleIndex = -1;
        
        for (int i = 0; i != player.audioTrackIndexes.count; i++) {
            if ([[player.audioTrackNames[i] lowercaseString] rangeOfString:@"english"].location != NSNotFound) {
                player.currentAudioTrackIndex = player.audioTrackIndexes[i];
                break;
            }
        }
    }
    self->prevState = self->player.state;
}

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification
{
}

@end
