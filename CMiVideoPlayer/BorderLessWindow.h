//
//  BorderLessWindow.h
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-13.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface BorderLessWindow : NSWindow {
@private
    int hideCount;
}

- (void)initTimer;

@end
