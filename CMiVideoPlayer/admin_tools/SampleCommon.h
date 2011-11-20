#ifndef _SAMPLECOMMON_H
#define _SAMPLECOMMON_H

#include "BetterAuthorizationSampleLib.h"

/////////////////////////////////////////////////////////////////

// Supported commands

#define kWakerSetWakeupEventCommand		"SetWakeupEvent"
    // authorization right name
    #define	kWakerSetWakeupEventRightName	"com.kodare.Waker.SetWakeupEvent"
	
    // request keys
    #define kWakerSetWakeupEventKeyDate	"Date" // CFDateRef

    // response keys (none) 

#define kWakerCancelWakeupEventCommand		"CancelWakeupEvent"
	// authorization right name
	#define	kWakerCancelWakeupEventRightName	"com.kodare.Waker.CancelWakeupEvent"

	// request keys
	#define kWakerCancelWakeupEventKeyDate	"Date" // CFDateRef

	// response keys (none)

#define kWakerSleepSystemEventCommand		"SleepSystem"
	// authorization right name
	#define	kWakerSleepSystemEventRightName	"com.kodare.Waker.SleepSystem"

	// request keys
	#define kWakerSleepSystemEventKeyDate	"Date" // CFDateRef

	// response keys (none)



// The kWakerCommandSet is used by both the app and the tool to communicate the set of 
// supported commands to the BetterAuthorizationSampleLib module.

extern const BASCommandSpec kWakerCommandSet[];


void PrintParams(
				 AuthorizationRef			auth,
				 const void *                userData,
				 CFDictionaryRef				request,
				 CFMutableDictionaryRef      response,
				 aslclient                   asl,
				 aslmsg                      aslMsg);
#endif
