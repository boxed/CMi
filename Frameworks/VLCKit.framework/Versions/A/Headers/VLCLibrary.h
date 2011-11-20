/*****************************************************************************
 * VLCLibrary.h: VLCKit.framework VLCLibrary header
 *****************************************************************************
 * Copyright (C) 2007 Pierre d'Herbemont
 * Copyright (C) 2007 the VideoLAN team
 * $Id: bc8852e39b63c85fda100315d4cc95ca0c1424f6 $
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

#import "VLCAudio.h"
#import "VLCMediaList.h"
#import "VLCMedia.h"

@class VLCAudio;

/**
 * The VLCLibrary is the base library of the VLCKit.framework.  This object provides a shared instance that exposes the
 * internal functionalities of libvlc and libvlc-control. The VLCLibrary object is instantiated automatically when
 * VLCKit.framework is loaded into memory.  Also, it is automatically destroyed when the VLCKit.framework is unloaded
 * from memory.
 *
 * Currently, the framework does not support multiple instances of VLCLibrary.  Furthermore, you cannot destroy any
 * instiantiation of VLCLibrary, as previously noted, this is done automatically by the dynamic link loader.
 */
@interface VLCLibrary : NSObject 
{
    void * instance;
}

/* Factories */
/**
 * Returns the library's shared instance.
 * \return The library's shared instance.
 */
+ (VLCLibrary *)sharedLibrary;

/**
 * Returns the library's version
 * \return The library version example "0.9.0-git Grishenko".
 */

@property (readonly) NSString * version;

/**
 * Returns the library's changeset
 * \return The library version example "adfee99".
 */

@property (readonly) NSString * changeset;

@end
