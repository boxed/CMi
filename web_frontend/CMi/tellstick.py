#
# ------------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <eirik.hodne at gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return, eirik.
# ------------------------------------------------------------------------------
#
#
# TellSticker version 0.5 (16th of February, 2010)
#
# ------------------------------------------------------------------------------
# Changelog:
# ------------------------------------------------------------------------------
#
# Version 0.6 (19th of February, 2010)
# - Have to reload the TelldusCore library every time we show the main menu (unfortunately9 to know if there are new or deleted devices
# 
# Version 0.5 (16th of February, 2010)
# - Hopefully fixes some navigational problems; http://forums.plexapp.com/index.php?/topic/12490-tellsticker-a-tellstick-plug-in/page__view__findpost__p__77053
# - Fixed weird "undo" behaviour; http://forums.plexapp.com/index.php?/topic/12490-tellsticker-a-tellstick-plug-in/page__view__findpost__p__77105
#
# Version 0.4 (Xth of February, 2010) 
# - Small memory clean-ups
#
# Version 0.3 (1th of February, 2010) 
# - Able to dim devices that supports it
#
# Version 0.2 (1th of February, 2010)
# - Complete rewrite using TelldusCore C library instead of tdtool command line app
# - Able to bell devices which supports it
#
# Version 0.1
# - Initial version
# - Able to turn devices on or off


# PMS plugin framework (only needed if using with Plex Media Server)
# from PMS import *
# from PMS.Objects import *
# from PMS.Shortcuts import *

import ctypes
from ctypes import *
from ctypes.util import find_library

TELLSTICK_TURNON 		= 1
TELLSTICK_TURNOFF		= 2
TELLSTICK_BELL			= 4
TELLSTICK_TOGGLE		= 8
TELLSTICK_DIM				= 16

TELLSTICK_SUCCESS		= 0
TELLSTICK_ERROR_UNKNOWN = -99

TELLSTICKER_SUPPORTED_FEATURES = TELLSTICK_TURNON | TELLSTICK_TURNOFF | TELLSTICK_BELL | TELLSTICK_DIM

class TellStick:

	def __init__(self,library_path):
		self.library = None
		self.SetLibraryPath(library_path)
		
	def SetLibraryPath(self,library_path):
		self.library_path = library_path
	
	def GetLibraryPath(self):
		return self.library_path
	
	def IsLibraryLoaded(self):
		return ctypes.util.find_library("TelldusCore") and not self.library == None
	
	def UnLoadLibrary(self):
		if(self.IsLibraryLoaded()):
			self.library.dlclose(self.library._handle)
		del self.library
		self.library = None
		
	def LoadLibrary(self):
		if (not self.IsLibraryLoaded()):
			#try:
			self.UnLoadLibrary()
			self.library = cdll.LoadLibrary(self.GetLibraryPath())
            # except OSError:
            #   Log("TellSticker: Could not load TelldusCore library from \"" + self.GetLibraryPath() + "\"")
            #   return 0
			self.library.tdInit()
		
		return 1
	
	def TurnOn(self,id):
		return c_int(self.Run(self.library.tdTurnOn, id)).value
	
	def TurnOff(self,id):
		return c_int(self.Run(self.library.tdTurnOff, id)).value
	
	def Bell(self,id):
		return c_int(self.Run(self.library.tdBell, id)).value
	
	def Dim(self,id,level):
		#level is in percentage from 0% to 100%. Actual values to the TelldusCore API use 0 - 255:
		level_int = (level/100) * 255
		
		if (level < 0 or level > 255):
			return 0
		
		return c_int(self.Run(self.library.tdDim, id, c_ubyte(level_int))).value
		
	def GetErrorString(self,retval):
		error_p = c_char_p(self.Run(self.library.tdGetErrorString,retval))
		error_str = error_p.value
		del error_p
		return error_str
		
	def Run(self,func,arg1 = None,arg2 = None):
		if(not self.LoadLibrary()):
			return 0
		
		if(arg2 != None):
			return func(arg1,arg2)
		elif (arg1 != None):
			return func(arg1)
		else:
			return func()
	
	def GetDevices(self):
		intNumberOfDevices = self.Run(self.library.tdGetNumberOfDevices)
		
		if(intNumberOfDevices < 1):
			return 0
			
		controls_data = [[0]*3 for i in range(intNumberOfDevices)]
		for i in range(intNumberOfDevices):
			id = self.GetDeviceId(i)
			controls_data[i-1][0] = id
			controls_data[i-1][1] = self.GetDeviceName(id)
			controls_data[i-1][2] = self.GetDeviceStatus(id)
		
		controls_data.sort(key = lambda x:x[0])
		return controls_data
	
	def GetDevice(self,id):
		control_data = [0,0,0]
		control_data[0] = id
		control_data[1] = self.GetDeviceName(id)
		control_data[2] = self.GetDeviceStatus(id)
		return control_data
		
	def GetDeviceId(self, index):
		return self.Run(self.library.tdGetDeviceId,index)
	
	def GetDeviceName(self, id):
		name_p = c_char_p(self.Run(self.library.tdGetName,id))
		name_str = name_p.value
		del name_p
		return name_str
		
	def GetDeviceFeatures(self,id):
		return self.Run(self.library.tdMethods,id,TELLSTICKER_SUPPORTED_FEATURES)

	def GetDeviceIdFromName(self,name):
		devices = self.GetDevices()
		
		for device in devices:
			if(device[1] == name):
				return device[0]
		
		return 0
			
	def GetDeviceStatus(self, id):
		return c_int(self.Run(self.library.tdLastSentCommand,id,TELLSTICKER_SUPPORTED_FEATURES)).value
		
	def GetDeviceStatusAsString(self, id):
		state = self.Run(self.GetDeviceStatus,id)
		if(state):
			if(state == TELLSTICK_TURNON):
				return "on"
			if(state == TELLSTICK_TURNOFF):
				return "off"
			if(state == TELLSTICK_BELL):
				return "bell"
			else:
				return "unknown"
		
		return 0

import sys
t = TellStick('/Library/Frameworks/TelldusCore.framework/TelldusCore')
t.LoadLibrary()
if len(sys.argv) < 3:
    print 'need two argument: <on/off> <device_id>'
    print 'devices:'
    for d in t.GetDevices():
        print '\t', d
else:
    if sys.argv[1] == 'on':
        t.TurnOn(int(sys.argv[2]))
    else:
        t.TurnOff(int(sys.argv[2]))