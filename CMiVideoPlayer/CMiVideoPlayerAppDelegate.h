//
//  CMiVideoPlayerAppDelegate.h
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "AppleRemote.h"
#import "BorderLessWindow.h"
#import "OverlayWindow.h"
#import "VolumeView.h"
#import "VideoPlayerProtocol.h"
#import "VLCKit/VLCkit.h"

typedef enum {
    webMode,
    movieMode
} Mode;

@interface CMiVideoPlayerAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
@private
    BorderLessWindow *window;
    OverlayWindow *HUDWindow;
 
    // web backend
    NSTask* webServer;
    NSPipe* webServerStdOut;
    NSPipe* webServerStdErr;
    NSFileHandle* webServerStdOutFile;
    NSFileHandle* webServerStdErrFile;

    // web GUI
    WebView *webView;
    
    // VideoPlayer
    id<VideoPlayerProtocol> movie;

    // movie player
    VolumeView* volumeView;
    BOOL isPlaying;
    NSTimer* progressTimer;
    NSString* movieCallbackURL;
    IBOutlet NSSlider* positionSlider;
    IBOutlet NSBox* controlsBox;
    IBOutlet NSButton* beginningButton;
    IBOutlet NSButton* rewindButton;
    IBOutlet NSButton* stopButton;
    IBOutlet NSButton* playPauseButton;
    IBOutlet NSButton* forwardButton;
    IBOutlet NSButton* endButton;
    BOOL showingOnScreenControls;

    // misc
    AppleRemote* remote;
    NSTimer* GUITimer;
    Mode mode;
    BOOL stickyOnScreenControls;
}

@property(assign) IBOutlet BorderLessWindow *window;
@property(assign) IBOutlet OverlayWindow *HUDWindow;
@property(assign) IBOutlet WebView *webView;
//@property(assign) IBOutlet QTMovieView *movieView;
//@property(retain) IBOutlet QTMovie *movie;
@property(retain) IBOutlet VolumeView* volumeView;
@property(retain) IBOutlet id<VideoPlayerProtocol> movie;

- (BOOL)readFromURL:(NSString*)s;
- (void)progressTimer:(NSTimer*)timer;
- (void)GUITimer:(NSTimer*)timer;
- (void)showWeb;
- (void)showMovie;
- (void)hideOnScreenControls;
- (void)showOnScreenControls;

- (IBAction)beginning:(id)sender;
- (IBAction)rewind:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)playPause:(id)sender;
- (IBAction)forward:(id)sender;
- (IBAction)end:(id)sender;

- (void)webServerWroteToStdOut:(NSNotification*)notification;

@end
