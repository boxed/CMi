#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>
#include <CoreServices/CoreServices.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include "BetterAuthorizationSampleLib.h"
#include "SampleCommon.h"

#define kAppKey "com.kodare.Waker"

void PrintParams(
				 AuthorizationRef			auth,
				 const void *                userData,
				 CFDictionaryRef				request,
				 CFMutableDictionaryRef      response,
				 aslclient                   asl,
				 aslmsg                      aslMsg)
{
	 CFIndex count;
	 CFIndex index;
	 const void **keys;
	 asl_log(asl, aslMsg, ASL_LEVEL_DEBUG, "waker: %li", CFDictionaryGetCount(request));
	 
	 count = CFDictionaryGetCount( (CFDictionaryRef) request);
	 keys = (const void **) malloc( count * sizeof(const void *));
	 if (keys != NULL) {
		 CFDictionaryGetKeysAndValues( (CFDictionaryRef) request, keys, NULL);
		 
		 for (index = 0; index < count; index++) {
			 char buffer[1024];
			 CFStringRef s = (CFStringRef)CFDictionaryGetValue( (CFDictionaryRef) request, keys[index]);
			 
			 CFStringGetCString(keys[index], buffer, 1024, kCFStringEncodingASCII);
			 asl_log(asl, aslMsg, ASL_LEVEL_DEBUG, "waker: %s", buffer);
			 
			 CFStringGetCString(s, buffer, 1024, kCFStringEncodingASCII);
			 asl_log(asl, aslMsg, ASL_LEVEL_DEBUG, "waker: %s", buffer);
		 }
		 free(keys);
	 }	
}
				 
/////////////////////////////////////////////////////////////////
static OSStatus DoSetWakeup(
	AuthorizationRef			auth,
    const void *                userData,
	CFDictionaryRef				request,
	CFMutableDictionaryRef      response,
    aslclient                   asl,
    aslmsg                      aslMsg
)
{	
	//OSStatus					retval = noErr;
	
	// Pre-conditions
	int res;
		
	assert(auth != NULL);
    // userData may be NULL
	assert(request != NULL);
	assert(response != NULL);
    // asl may be NULL
    // aslMsg may be NULL
	
	if ( !CFDictionaryContainsKey(request, CFSTR(kWakerSetWakeupEventKeyDate)) ) { return 10; }
	
	res = IOPMSchedulePowerEvent((CFDateRef)CFDictionaryGetValue((CFDictionaryRef)request, CFSTR(kWakerSetWakeupEventKeyDate)), CFSTR(kAppKey), CFSTR(kIOPMAutoWake));
	
	if (res == kIOReturnSuccess)
	{
		printf("Daily Wakeup Call successfully installed\n");
	}
	else 
	{
		asl_log(asl, aslMsg, ASL_LEVEL_DEBUG, "Failed to set wakeup date. Errcode: %x", res);
		return res;
	}

	return noErr;
}

static OSStatus DoCancelWakeup(
							AuthorizationRef			auth,
							const void *                userData,
							CFDictionaryRef				request,
							CFMutableDictionaryRef      response,
							aslclient                   asl,
							aslmsg                      aslMsg
							)
{	
	//OSStatus					retval = noErr;
	
	// Pre-conditions
	int res;
	
	assert(auth != NULL);
    // userData may be NULL
	assert(request != NULL);
	assert(response != NULL);
    // asl may be NULL
    // aslMsg may be NULL
	
	if ( !CFDictionaryContainsKey(request, CFSTR(kWakerSetWakeupEventKeyDate)) ) { return 10; }
	
	res = IOPMCancelScheduledPowerEvent((CFDateRef)CFDictionaryGetValue((CFDictionaryRef)request, CFSTR(kWakerSetWakeupEventKeyDate)), CFSTR(kAppKey), CFSTR(kIOPMAutoWake));
	
	if (res == kIOReturnSuccess)
	{
		printf("Daily Wakeup Call successfully installed\n");
	}
	else 
	{
		asl_log(asl, aslMsg, ASL_LEVEL_DEBUG, "Failed to set wakeup date. Errcode: %x", res);
		return res;
	}
	
	return noErr;
}

static OSStatus SleepSystem(
							   AuthorizationRef			auth,
							   const void *                userData,
							   CFDictionaryRef				request,
							   CFMutableDictionaryRef      response,
							   aslclient                   asl,
							   aslmsg                      aslMsg
							   )
{	
	io_connect_t fb = IOPMFindPowerManagement(MACH_PORT_NULL); 
	IOPMSleepSystem(fb);
	return noErr;
}


/////////////////////////////////////////////////////////////////
#pragma mark ***** Tool Infrastructure

/*
    IMPORTANT
    ---------
    This array must be exactly parallel to the kWakerCommandSet array 
    in "SampleCommon.c".
*/

static const BASCommandProc kWakerCommandProcs[] = {
    DoSetWakeup,
	DoCancelWakeup,
	SleepSystem,
    NULL
};

int main(int argc, char **argv)
{
    // Go directly into BetterAuthorizationSampleLib code.
	
    // IMPORTANT
    // BASHelperToolMain doesn't clean up after itself, so once it returns 
    // we must quit.
    
	return BASHelperToolMain(kWakerCommandSet, kWakerCommandProcs);
}
