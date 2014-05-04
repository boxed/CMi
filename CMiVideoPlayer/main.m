//
//  main.m
//  CMiVideoPlayer
//
//  Created by Anders Hovmöller on 2011-06-11.
//  Copyright 2011 Hovmöller. See LICENSE file for license.
//

#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[])
{

    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"WebKitDeveloperExtras"]];
    return NSApplicationMain(argc, (const char **)argv);
}
