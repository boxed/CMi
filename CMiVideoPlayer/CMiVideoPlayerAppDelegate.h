//
//  CMiVideoPlayerAppDelegate.h
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-11.
//  Copyright 2011 Hovmöller. See LICENSE file for license.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "AppleRemote.h"
#import "BorderLessWindow.h"
#import "OverlayWindow.h"
#import "VolumeView.h"
#import "VideoPlayerProtocol.h"
#import "VLCKit/VLCkit.h"
#import <CoreLocation/CoreLocation.h>

typedef enum {
    webMode,
    movieMode
} Mode;

@interface CMiVideoPlayerAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, CLLocationManagerDelegate> {
@private
    BorderLessWindow *window;
    OverlayWindow *HUDWindow;
 
    // web backend
    NSPipe* webServerStdOut;
    NSFileHandle* webServerStdOutFile;
    BOOL hasStarted;

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
    CLLocationManager* locationManager;
    NSMutableString* outputBuffer;
    NSOperationQueue* queue;
    NSTimer* searchForFilesTimer;
    NSThread* pythonThread;
    
}

@property(assign) IBOutlet BorderLessWindow *window;
@property(assign) IBOutlet OverlayWindow *HUDWindow;
@property(assign) IBOutlet WebView *webView;
@property(retain) IBOutlet VolumeView* volumeView;
@property(retain) IBOutlet id<VideoPlayerProtocol> movie;
@property (assign) IBOutlet NSWindow *startupWindow;

- (BOOL)readFromURL:(NSString*)s;
- (void)progressTimer:(NSTimer*)timer;
- (void)GUITimer:(NSTimer*)timer;
- (void)searchForFilesTimer:(NSTimer*)timer;
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
- (void)keyDown:(NSEvent *)theEvent;

@end
