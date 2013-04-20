//
//  CMiVideoPlayerAppDelegate.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "CMiVideoPlayerAppDelegate.h"
#import "QuickTimePlayer.h"
#import "VLCVideoPlayer.h"

static const float ON_SCREEN_CONTROL_ALPHA = 0.6;

void key(int code)
{
    CGEventRef a = CGEventCreateKeyboardEvent(NULL, code, true);
    CGEventRef b = CGEventCreateKeyboardEvent(NULL, code, false);
    CGEventPost(kCGHIDEventTap, a);
    CGEventPost(kCGHIDEventTap, b);
    CFRelease(a);
    CFRelease(b);
}

@implementation CMiVideoPlayerAppDelegate

@synthesize window;
@synthesize HUDWindow;
@synthesize webView;
@synthesize volumeView;
@synthesize movie;

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(webServerWroteToStdOut:) name:NSFileHandleReadCompletionNotification object:nil];
    stickyOnScreenControls = NO;
    
    outputBuffer = [[NSMutableString stringWithCapacity:1000] retain];
    
    // Set up webserver backend
    NSArray* arguments = [NSArray arrayWithObjects:@"-u", @"CMi/manage.py", @"runserver", @"--noreload", nil];
    webServer = [[NSTask alloc] init];
    [webServer setLaunchPath:@"/usr/bin/python"];
    NSString* foo = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"web_frontend"];
    [webServer setCurrentDirectoryPath:foo];
    [webServer setArguments:arguments];
    webServerStdOut = [NSPipe pipe];
    webServerStdErr = [NSPipe pipe];
    webServerStdOutFile = [webServerStdOut fileHandleForReading];
    webServerStdErrFile = [webServerStdErr fileHandleForReading];
    [webServerStdOutFile readInBackgroundAndNotify];
    [webServerStdErrFile readInBackgroundAndNotify];
    [webServer setStandardOutput:webServerStdOut];
    [webServer setStandardError:webServerStdErr];
    [webServer launch];
    
    // Set up rest of GUI
    self.window.delegate = self;
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

    WebPreferences* preferences = [[WebPreferences alloc] initWithIdentifier:@"CMi"];
    preferences.usesPageCache = NO;
    preferences.cacheModel = WebCacheModelDocumentViewer;
    [self.webView setPreferences:preferences];
    [preferences release];
    [[NSURLCache sharedURLCache] setMemoryCapacity:0]; 
    [[NSURLCache sharedURLCache] setDiskCapacity:0]; 
    [self.webView setFrameLoadDelegate:self];
    
    [self hideOnScreenControls];
    
    remote = [[AppleRemote alloc] initWithDelegate:self];
    [remote setDelegate:self];
    self->progressTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(progressTimer:) userInfo:nil repeats:YES];
    self->GUITimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(GUITimer:) userInfo:nil repeats:YES];
    CGDisplayHideCursor(kCGDirectMainDisplay);
    [self->window initTimer];
    
    [[self->beginningButton cell] setHighlightsBy:0];
    [[self->rewindButton cell] setHighlightsBy:0];
    [[self->stopButton cell] setHighlightsBy:0];
    [[self->playPauseButton cell] setHighlightsBy:0];
    [[self->forwardButton cell] setHighlightsBy:0];
    [[self->endButton cell] setHighlightsBy:0];

    //[self.window toggleFullScreen:self];
    [self->HUDWindow setDelegate:self];
    [self->HUDWindow setFloatingPanel:YES];
    
    //self->movie = [[[QuickTimePlayer alloc] initWithParentWindow:self->window] retain];
    [window setFrame:[[NSScreen mainScreen] frame] display:NO];
    
    // Register delegate as scriptable object for javascript
    [[self.webView windowScriptObject] setValue:self forKey:@"CMiDelegate"];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
    [self->remote startListening:self];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification
{
    [self->remote stopListening:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [webServer terminate];
}

- (void)webServerWroteToStdOut:(NSNotification*)notification
{
    if ([notification object] == webServerStdErrFile)
        [webServerStdErrFile readInBackgroundAndNotify];
    else if ([notification object] == webServerStdOutFile)
        [webServerStdOutFile readInBackgroundAndNotify];
    NSData* data = [[notification userInfo] valueForKey:NSFileHandleNotificationDataItem];
    NSString* newStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [outputBuffer appendString:newStr];
    [newStr release];
    NSRange r;
    while (true) {
        r = [outputBuffer rangeOfString:@"\n"];
        if (r.location == NSNotFound) {
            return;
        }
        newStr = [outputBuffer substringToIndex:r.location];
        [outputBuffer deleteCharactersInRange:NSMakeRange(0, r.location+1)];
        
        if ([newStr length]) {
            if ([newStr rangeOfString:@"Quit the server with CONTROL-C"].location != NSNotFound) {
                NSLog(@"Server started");
                NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8000/"]];
                [[self.webView mainFrame] loadRequest:request];

                // Ask for location
                locationManager = [[CLLocationManager alloc] init];
                locationManager.delegate = self;
                [locationManager startUpdatingLocation];
            }
            else {
                NSLog(@"%@", newStr);
            }
        }
    }
}

- (void)handleURLEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    NSString* s = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    s = [s stringByReplacingOccurrencesOfString:@"CMiVideoPlayer://" withString:@"file://"];
    if ([s hasPrefix:@"file://http://"]) {
        s = [s stringByReplacingOccurrencesOfString:@"file://" withString:@""];
    }
    NSLog(@"Handling url: %@", s);
    if ([@"file://sleep" isEqualToString:s]) {
        //[self sleepSystem];
    }
    else if ([@"file://refresh" isEqualToString:s]) {
        //key(46); // R key
        key(48); // R key
    }
    else if ([@"file://back" isEqualToString:s]) {
        key(53); // ESC key
    }
    else {
        [self readFromURL:s];
    }
}

+ (NSDictionary*)queryDictionaryFromString:(NSString*)s usingEncoding:(NSStringEncoding)encoding
{ 
    NSCharacterSet* delimiterSet = [NSCharacterSet characterSetWithCharactersInString:@"&;"] ;
    NSMutableDictionary* pairs = [NSMutableDictionary dictionary] ;
    NSScanner* scanner = [[NSScanner alloc] initWithString:s] ;
    while (![scanner isAtEnd]) {
        NSString* pairString ;
        [scanner scanUpToCharactersFromSet:delimiterSet
                                intoString:&pairString] ;
        [scanner scanCharactersFromSet:delimiterSet intoString:NULL] ;
        NSArray* kvPair = [pairString componentsSeparatedByString:@"="] ;
        if ([kvPair count] == 2) {
            NSString* key = [[kvPair objectAtIndex:0] stringByReplacingPercentEscapesUsingEncoding:encoding] ; NSString* value = [[kvPair objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:encoding] ;
            [pairs setObject:value forKey:key] ;
        }
    }
    
    [scanner release];
    
    return [NSDictionary dictionaryWithDictionary:pairs] ;
}

- (BOOL)readFromURL:(NSString*)s
{
    NSURL* url = [NSURL URLWithString:s];
    NSString* query = [url query];
    NSDictionary* params = [NSDictionary dictionary];
    if (query != nil) {
        params = [CMiVideoPlayerAppDelegate queryDictionaryFromString:query usingEncoding:NSUTF8StringEncoding];
        url = [NSURL URLWithString:[s substringToIndex:[s rangeOfString:@"?"].location]];
    }

    assert(self->movie == nil);
    self->movie = [[[VLCVideoPlayer alloc] initWithParentWindow:self->window] retain];
    [self->movie openURL:url];
    float volume = [[NSUserDefaults standardUserDefaults] floatForKey:@"volume"];
    [self->movie setVolume:volume];
        
    [self showMovie];
        
    float time = 0;
    if ([params valueForKey:@"seconds"] != nil)
        time = [[params valueForKey:@"seconds"] floatValue];
    [self->movie setCurrentTime:time];
    self->movieCallbackURL = [[params objectForKey:@"callback"] retain];
        
    [self->movie play];
    self->isPlaying = YES;

    return TRUE;
}

- (IBAction)beginning:(id)sender
{
    [self->movie setCurrentTime:0.0];
}

- (IBAction)rewind:(id)sender
{
    [self->movie stepBackward];
}

- (IBAction)stop:(id)sender
{
    [self->movie stop];
    self->isPlaying = NO;
    [self hideOnScreenControls];
    [self showWeb];
    [self->movie release];
    self->movie = nil;
}

- (IBAction)playPause:(id)sender
{
    [self->movie pause];
    self->isPlaying = !self->isPlaying;
    if (self->isPlaying) {
        [self->playPauseButton setImage:[NSImage imageNamed:@"pause"]];
    }
    else {
        [self->playPauseButton setImage:[NSImage imageNamed:@"play"]];
    }
}

- (IBAction)forward:(id)sender
{
    [self->movie stepForward];
}

- (IBAction)end:(id)sender
{
    if (self->isPlaying) {
        [self playPause:self];
    }
    [self->movie setCurrentTime:[self->movie duration]-1000];
}

void setAlpha(NSView* v)
{
    if ([[v window] firstResponder] == v) {
        [[v animator] setAlphaValue:ON_SCREEN_CONTROL_ALPHA];
    }
    else {
        [[v animator] setAlphaValue:ON_SCREEN_CONTROL_ALPHA / 2];
    }
}

- (void)refreshOnScreenControls
{
    [self->volumeView setNeedsDisplay:YES];
    if (self->showingOnScreenControls && self->mode == movieMode) {
        [self->volumeView setAlphaValue:ON_SCREEN_CONTROL_ALPHA];
        setAlpha(self->playPauseButton);
        setAlpha(self->stopButton);
        setAlpha(self->beginningButton);
        setAlpha(self->rewindButton);
        setAlpha(self->forwardButton);
        setAlpha(self->endButton);
        
        [self->positionSlider setMaxValue:[self->movie duration]];
        [self->positionSlider setFloatValue:[self->movie currentTime]];
    }
}

- (void)toggleOnScreenControls
{
    if (self->showingOnScreenControls) {
        stickyOnScreenControls = NO;
        [self hideOnScreenControls];
    }
    else {
        [self showOnScreenControls];
        stickyOnScreenControls = YES;
    }
    [self refreshOnScreenControls];
}

- (void)forceHideOnScreenControls
{
    [[self->HUDWindow animator] setAlphaValue:0.0];
    self->showingOnScreenControls = NO;
}

- (void)hideOnScreenControls
{
    if (!stickyOnScreenControls) {
        [self forceHideOnScreenControls];
    }
}

- (void)showOnScreenControls
{
    if (self->mode == movieMode) {
        [self->window makeKeyWindow];
        [self refreshOnScreenControls];
        [[self->HUDWindow animator] setAlphaValue:ON_SCREEN_CONTROL_ALPHA];
        [self->HUDWindow orderFront:self];
        [self->HUDWindow makeFirstResponder:self->playPauseButton];
        [self->HUDWindow makeKeyWindow];
        
        self->showingOnScreenControls = YES;
    }
}

- (void)progressTimer:(NSTimer*)timer
{
    if (self->isPlaying) {
        NSString* urlprefix = [NSString stringWithFormat:@"http://127.0.0.1:8000/%@", self->movieCallbackURL];
        float current = [self->movie currentTime];
        float end = [self->movie duration];
        if (end < 2) {
            NSLog(@"Prevented early stop of movie");
            return;
        }
        NSURL* url = nil;
        if (fabs(current - end) < 3000) {
            url = [NSURL URLWithString:[urlprefix stringByAppendingString:@"/ended"]];
            [self stop:self];
        }
        else {
            url = [NSURL URLWithString:[urlprefix stringByAppendingFormat:@"/position/%d", (int)current]];
        }
        [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url] queue:nil completionHandler:^(NSURLResponse* r, NSData* d, NSError* e){}];
    }
}

- (void)GUITimer:(NSTimer*)timer
{
    [self refreshOnScreenControls];
}

- (void)dealloc
{
    if (movie) {
        [movie release];
    }
    [super dealloc];
}

- (void)showWeb
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"/* From Obj-C: refresh when showing webView again */ refresh();"];
    [self->movie setHidden:YES];
    [self.webView setHidden:NO];
    [self.window makeFirstResponder:self.webView];
    self->mode = webMode;
    [self forceHideOnScreenControls];
}

- (void)showMovie
{
    [self->movie setHidden:NO];
    [self.webView setHidden:YES];
    self->mode = movieMode;
}

- (void)setVolume:(float)volume
{
    [[NSUserDefaults standardUserDefaults] setFloat:volume forKey:@"volume"];
    [self->movie setVolume:volume];
}


- (void)raiseVolume
{
    float volume = [[NSUserDefaults standardUserDefaults] floatForKey:@"volume"] + 0.05;
    if (volume > 1.0)
        volume = 1.0;
    [self setVolume:volume];
}

- (void)lowerVolume
{
    float volume = [[NSUserDefaults standardUserDefaults] floatForKey:@"volume"] - 0.05;
    if (volume < 0.0)
        volume = 0.0;
    [self setVolume:volume];
}

- (void)navigateMenuRight:(BOOL)right
{
    const int NUM_BUTTONS = 6;
    NSButton* buttons[6] = {
        self->beginningButton,
        self->rewindButton,
        self->stopButton,
        self->playPauseButton,
        self->forwardButton,
        self->endButton
    };
    int currentButton = 0;
    for (int i = 0; i != NUM_BUTTONS; i++) {
        if (buttons[i] == [self->HUDWindow firstResponder]) {
            currentButton = i;
            break;
        }
    }
    if (!right) {
        if (currentButton > 0)
            currentButton--;
    }
    else {
        if (currentButton < NUM_BUTTONS-1)
            currentButton++;
    }
    [self->HUDWindow makeFirstResponder:buttons[currentButton]];
    [self refreshOnScreenControls];    
}

- (void)keyDown:(NSEvent *)theEvent
{
    if (self->mode == movieMode) {
        if (self->showingOnScreenControls) {
            switch ([[theEvent characters] characterAtIndex:0]) {
                case ' ':
                    [[(NSButton*)[self->HUDWindow firstResponder] cell] performClick:self];
                    break;
                case 'm':
                    [self toggleOnScreenControls];
                    break;
                default: {
                    switch([theEvent keyCode]) {
                        case 126:       // up arrow
                            [self raiseVolume];
                            break;
                        case 125:       // down arrow
                            [self lowerVolume];
                            break;
                        case 124:       // right arrow
                            [self navigateMenuRight:TRUE];
                            break;
                        case 123:       // left arrow
                            [self navigateMenuRight:FALSE];
                            break;
                    }
                }
            }
        }
        else {            
            switch ([[theEvent characters] characterAtIndex:0]) {
                case ' ':
                    [self playPause:self];
                    break;
                case 'm':
                    [self toggleOnScreenControls];
                    break;
                default: {
                    switch([theEvent keyCode]) {
                        case 126:       // up arrow
                            [self raiseVolume];
                            break;
                        case 125:       // down arrow
                            [self lowerVolume];
                            break;
                        default:
                            break;
                    }
                }
            }
        }
    }
}

#pragma mark Remote control
- (void)sendRemoteButtonEvent:(RemoteControlEventIdentifier) event pressedDown:(BOOL)pressedDown remoteControl:(RemoteControl*)remoteControl
{
    if (self->mode == movieMode) {
        if (event == kRemoteButtonMenu_Hold) {
            [self stop:self];   
        }
        if (pressedDown == NO) {
            if (event == kRemoteButtonMenu) {
                [self toggleOnScreenControls];
            }
            else if (event == kRemoteButtonPlus) {
                [self raiseVolume];
            }
            else if (event == kRemoteButtonMinus) {
                [self lowerVolume];
            }
            if (self->showingOnScreenControls) {
                if (event == kRemoteButtonPlay) {
                    [((NSButton*)[self->HUDWindow firstResponder]) performClick:self];
                }
                else if (event == kRemoteButtonLeft || event == kRemoteButtonRight) {
                    [self navigateMenuRight:(event == kRemoteButtonRight)];
                }
            }
            else {
                if (event == kRemoteButtonPlay) {
                    [self playPause:self];
                }
                else if (event == kRemoteButtonLeft) {
                    if (self->isPlaying) { // skip a commercial/intro
                        [self rewind:self];
                    }
                    else { // step single frame when paused
                        [self->movie stepBackward];
                    }
                }
                else if (event == kRemoteButtonRight) {
                    if (self->isPlaying) { // skip a commercial/intro
                        [self forward:self];
                    }
                    else { // step single frame when paused
                        [self->movie stepForward];
                    }
                }
            }
        }
    }
    else {
        if (pressedDown == NO) {
            if (event == kRemoteButtonMenu)         key(53); // esc
            else if (event == kRemoteButtonPlus)    key(126);
            else if (event == kRemoteButtonMinus)   key(125);
            else if (event == kRemoteButtonLeft)    key(123);
            else if (event == kRemoteButtonRight)   key(124);
        }
        else if (event == kRemoteButtonPlay)    
            key(36);
    }
}

#pragma mark NSWindow delegate
- (void)windowDidResize:(NSNotification *)notification
{
    [self->HUDWindow setFrame:[[notification object] frame] display:TRUE];
    
    
/*    if ([self->window backingScaleFactor] > 1) {
        CGFloat s = [self->window backingScaleFactor];
        CGAffineTransform transform = CGAffineTransformMakeScale(1/s, 1/s);
        [self->webView setWantsLayer:YES];
        [[self->webView layer] setAffineTransform:transform];
        NSRect frame = [[self->window contentView] frame];
        frame.size.width *= s;
        frame.size.height *= s;
        [self->webView setFrame:frame];
    }
*/
}

#pragma mark WebView delegate
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    [self showWeb];
    [window makeFirstResponder:self.webView];
    [window makeKeyAndOrderFront:self];
    [window toggleFullScreen:self];
}

#pragma mark location manager delegate
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    if (oldLocation == nil || [newLocation distanceFromLocation:oldLocation] > 1000) {
        NSString* url = [NSString stringWithFormat:@"http://127.0.0.1:8000/set_location/?location=%f,%f", [newLocation coordinate].latitude, [newLocation coordinate].longitude];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        [NSURLConnection sendAsynchronousRequest:request queue:nil completionHandler:^(NSURLResponse* r, NSData* d, NSError* e){}];
        [self.webView stringByEvaluatingJavaScriptFromString:@"/* From Obj-C: refresh to update location */ refresh();"];
    }
}

@end
