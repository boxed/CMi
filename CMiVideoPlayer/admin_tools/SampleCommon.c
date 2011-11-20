#include "SampleCommon.h"

/*
	I originally generated the "SampleAuthorizationPrompts.strings" file by running 
	the following command in Terminal.  genstrings doesn't notice that the 
	CFCopyLocalizedStringFromTableInBundle is commented out, which is good for 
	my purposes.
	
    $ genstrings SampleCommon.c -o en.lproj

    CFCopyLocalizedStringFromTableInBundle(CFSTR("GetUIDsPrompt"),          "SampleAuthorizationPrompts", b, "prompt included in authorization dialog for the GetUIDs command")
    CFCopyLocalizedStringFromTableInBundle(CFSTR("LowNumberedPortsPrompt"), "SampleAuthorizationPrompts", b, "prompt included in authorization dialog for the LowNumberedPorts command")
*/

/*
    IMPORTANT
    ---------
    This array must be exactly parallel to the kWakerCommandProcs array 
    in "SampleTool.c".
*/

const BASCommandSpec kWakerCommandSet[] = {
    {	kWakerSetWakeupEventCommand,         // commandName
        kWakerSetWakeupEventRightName,       // rightName
        "allow", // rightDefaultRule    -- by default, you have to have admin credentials (see the "default" rule in the authorization policy database, currently "/etc/authorization")
        "WakeAuthorizationPrompt",				// rightDescriptionKey -- key for custom prompt in "SampleAuthorizationPrompts.strings
        NULL                                    // userData
	},

	{	kWakerCancelWakeupEventCommand,         // commandName
        kWakerCancelWakeupEventRightName,       // rightName
        "allow", // rightDefaultRule    -- by default, you have to have admin credentials (see the "default" rule in the authorization policy database, currently "/etc/authorization")
        "WakeAuthorizationPrompt",				// rightDescriptionKey -- key for custom prompt in "SampleAuthorizationPrompts.strings
        NULL                                    // userData
	},

	{	kWakerSleepSystemEventCommand,         // commandName
        kWakerSleepSystemEventRightName,       // rightName
        "allow", // rightDefaultRule    -- by default, you have to have admin credentials (see the "default" rule in the authorization policy database, currently "/etc/authorization")
        "WakeAuthorizationPrompt",				// rightDescriptionKey -- key for custom prompt in "SampleAuthorizationPrompts.strings
        NULL                                    // userData
	},
	
    {	NULL,                                   // the array is null terminated
        NULL, 
        NULL, 
        NULL,
        NULL
	}
};
