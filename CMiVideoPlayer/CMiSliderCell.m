//
//  CMiSliderCell.m
//  test
//
//  Created by Anders Hovmöller on 2011-06-17.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "CMiSliderCell.h"


@implementation CMiSliderCell

- (BOOL)_usesCustomTrackImage
{
    return YES;
}

- (void)drawKnob:(NSRect)knobRect
{
}

- (void)drawBarInside:(NSRect)aRect flipped:(BOOL)flipped
{
    [[NSColor whiteColor] set];
    aRect.size.width -= [self knobThickness];
    if ([self maxValue]) {
        aRect.size.width *= [self floatValue]/[self maxValue];
    }
    else {
        aRect.size.width = 1;
    }
    aRect.size.width += [self knobThickness]/2;
    aRect.size.height /= 2;
    aRect.origin.y += aRect.size.height/2;
    [[NSBezierPath bezierPathWithRect:aRect] fill];
}

@end
