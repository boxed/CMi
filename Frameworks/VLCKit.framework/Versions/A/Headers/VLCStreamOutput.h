/*****************************************************************************
 * VLCStreamOutput.h: VLCKit.framework VLCStreamOutput header
 *****************************************************************************
 * Copyright (C) 2008 Pierre d'Herbemont
 * Copyright (C) 2008 the VideoLAN team
 * $Id: ab1d5e37fb20eae05ea0c5d12d1b57e7883aa6f3 $
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

extern NSString * VLCDefaultStreamOutputRTSP;
extern NSString * VLCDefaultStreamOutputRTP;
extern NSString * VLCDefaultStreamOutputRTP;

@interface VLCStreamOutput : NSObject {
    NSMutableDictionary * options;
}

- (id)initWithOptionDictionary:(NSDictionary *)dictionary;
+ (id)streamOutputWithOptionDictionary:(NSDictionary *)dictionary;

+ (id)rtpBroadcastStreamOutputWithSAPAnnounce:(NSString *)announceName;
+ (id)rtpBroadcastStreamOutput;
+ (id)ipodStreamOutputWithFilePath:(NSString *)filePath;
+ (id)streamOutputWithFilePath:(NSString *)filePath;
+ (id)mpeg2StreamOutputWithFilePath:(NSString *)filePath;
+ (id)mpeg4StreamOutputWithFilePath:(NSString *)filePath;

@end
