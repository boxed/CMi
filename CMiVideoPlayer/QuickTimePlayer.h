//
//  QuickTimePlayer.h
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-10-02.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "VideoPlayerProtocol.h"
#import <QTKit/QTKit.h>

@interface QuickTimePlayer : NSView<VideoPlayerProtocol> {
    QTMovieView *movieView;
    QTMovie *movie;    
    NSSize originalSize;
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
- (void)setHidden:(BOOL)b;

- (float)volume;
- (float)currentTime;
- (float)duration;

@property(assign) IBOutlet QTMovieView *movieView;
@property(retain) IBOutlet QTMovie *movie;


@end
