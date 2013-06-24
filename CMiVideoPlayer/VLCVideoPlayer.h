//
//  VLCVideoPlayer.h
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-09.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <VLCKit/VLCKit.h>
#import "VideoPlayerProtocol.h"

@interface VLCVideoPlayer : NSObject <VideoPlayerProtocol, VLCMediaPlayerDelegate>
{
    VLCVideoView* view;
    VLCMediaPlayer* player;
    NSWindow* window;
    BOOL isPaused;
    VLCMediaPlayerState prevState;
}

- (id)initWithParentWindow:(NSWindow*)window;
- (void)openURL:(NSURL*)url;
- (void)play;
- (void)pause;
- (void)stop;
- (void)setVolume:(float)volume;
- (void)setCurrentTime:(float)time;
- (void)stepForward;
- (void)stepBackward;

- (float)volume;
- (float)currentTime;
- (float)duration;

- (void)setHidden:(BOOL)b;

@end
