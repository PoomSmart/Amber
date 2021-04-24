#import "../PSHeader/Misc.h"
#import <HBLog.h>
#import "Header.h"

#import <dlfcn.h>
#import <mach/port.h>
#import <mach/kern_return.h>

// Tweak
// 0 - white only (default)
// 1 - both
// 2 - amber only

/**
    This tweak can tell the camera to use only the amber LED for torch.
    In normal situations, the camera decides whether to turn on the amber LED if the scene temperature matches.
    Amber tricks the camera into thinking that the scene always matches amber lighting condition.
    When the scene is determined to be the warmest (percentile >= 100), only amber LED will turn on.

    However, the concept differs for iPhone 7 (H9ISP) and newer which include quad-LEDs (two white's and two amber's).
    Faking the scene condition is no longer relevant, as SetTorchLevel() calls a different function that does no longer
    rely on the scene condition, but surprisingly presents another neat solution to enabling the amber light.
    The function is SetIndividualTorchLEDLevels() that can literally be used to manipulate the brightness level of each individual LED.

    The levels are represented as a single 32-bit integer. This integer is seperated into 8-bit chunks.
    From left to right, the 1st and the 3rd chunks specify the brightness level of the white LEDs (0x00 as min and 0xFF as max).
    Similarly, the 2nd and the 4th chunks specify the brightness level of the amber LEDs (0x00 as min and 0xFF as max).
    Easy enough, having only amber light requires us to set the integer level to be 0x00hh00hh.
    By default, H9ISP cameras ensure that the brightness format is in 0xhh00hh00, locking down any non-jailbroken attempts.
**/

typedef struct HXISPCaptureStream *HXISPCaptureStreamRef;
typedef struct HXISPCaptureDevice *HXISPCaptureDeviceRef;
typedef struct HXISPCaptureGroup *HXISPCaptureGroupRef;

int (*SetTorchLevel)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchLevelWithGroup)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchColor)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef) = NULL;
SInt32 (*GetCFPreferenceNumber)(CFStringRef const, CFStringRef const, SInt32) = NULL;

int (*SetIndividualTorchLEDLevels)(void *, unsigned int, unsigned int) = NULL;

Boolean enabled() {
    return GetCFPreferenceNumber(key, kDomain, 0) != 0;
}

Boolean both() {
    return GetCFPreferenceNumber(bothKey, kDomain, 0) != 0;
}

void SetTorchLevelHook(int result, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureDeviceRef device) {
    if (!result && level && SetIndividualTorchLEDLevels == NULL && enabled()) {
        // If torch level setting is successful, we can override the torch color
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        int val = 100; // from 0 (coolest) to 100 (warmest)
        CFNumberRef threshold = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &val);
        CFDictionaryAddValue(dict, CFSTR("WarmLEDPercentile"), threshold);
        // Now tell the camera the "fake" scene condition
        SetTorchColor(dict, stream, device);
        CFRelease(threshold);
        CFRelease(dict);
    }
}

%group SetTorchLevelHook

%hookf(int, SetTorchLevel, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureDeviceRef device) {
    int result = %orig(level, stream, device);
    SetTorchLevelHook(result, level, stream, device);
    return result;
}

%end

%group SetTorchLevelWithGroupHook

%hookf(int, SetTorchLevelWithGroup, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureGroupRef group, HXISPCaptureDeviceRef device) {
    int result = %orig(level, stream, group, device);
    SetTorchLevelHook(result, level, stream, device);
    return result;
}

%end

%group Dual

int (*SetTorchColorMode)(void *, unsigned int, unsigned short, unsigned short);
%hookf(int, SetTorchColorMode, void *arg0, unsigned int arg1, unsigned short mode, unsigned short level) {
    return %orig(arg0, arg1, enabled() && both() ? 1 : mode, level);
}

%end

%group Quad

%hookf(int, SetIndividualTorchLEDLevels, void *arg0, unsigned int arg1, unsigned int levels) {
    // both: 0xhh00hh00 -> 0xhhhhhhhh
    // amber only: 0xhh00hh00 -> 0x00hh00hh
    unsigned int finalLevels = levels && enabled() ? (both() ? (levels | (levels >> 8)) : (levels >> 8)) : levels;
    return %orig(arg0, arg1, finalLevels);
}

%end

%ctor {
    int HVer = 0;
    void *IOKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (IOKit) {
        mach_port_t *kIOMasterPortDefault = (mach_port_t *)dlsym(IOKit, "kIOMasterPortDefault");
        CFMutableDictionaryRef (*IOServiceMatching)(const char *name) = (CFMutableDictionaryRef (*)(const char *))dlsym(IOKit, "IOServiceMatching");
        mach_port_t (*IOServiceGetMatchingService)(mach_port_t masterPort, CFDictionaryRef matching) = (mach_port_t (*)(mach_port_t, CFDictionaryRef))dlsym(IOKit, "IOServiceGetMatchingService");
        kern_return_t (*IOObjectRelease)(mach_port_t object) = (kern_return_t (*)(mach_port_t))dlsym(IOKit, "IOObjectRelease");
        if (kIOMasterPortDefault && IOServiceGetMatchingService && IOObjectRelease) {
            char AppleHXCamIn[14];
            for (HVer = 13; HVer > 9; --HVer) {
                sprintf(AppleHXCamIn, "AppleH%dCamIn", HVer);
                mach_port_t hx = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching(AppleHXCamIn));
                if (hx) {
                    IOObjectRelease(hx);
                    break;
                }
            }
            if (HVer == 9) {
                mach_port_t h9 = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching("AppleH9CamIn"));
                if (h9)
                    IOObjectRelease(h9);
                else {
                    mach_port_t h6 = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching("AppleH6CamIn"));
                    if (h6) {
                        HVer = 6;
                        IOObjectRelease(h6);
                    } else
                        HVer = 0;
                }
            }
        }
        dlclose(IOKit);
        HBLogDebug(@"Detected ISP version: %d", HVer);
    }
    if (HVer == 0) return;
    char imagePath[49];
    sprintf(imagePath, "/System/Library/MediaCapture/H%dISP.mediacapture", HVer);
    dlopen(imagePath, RTLD_NOW);
    MSImageRef hxRef = MSGetImageByName(imagePath);
    switch (HVer) {
        case 9: {
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(hxRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP18H9ISPCaptureDevice");
            if (SetTorchLevel == NULL)
                SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))MSFindSymbol(hxRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP17H9ISPCaptureGroupP18H9ISPCaptureDevice");
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, "__ZN5H9ISP26H9ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
            SetIndividualTorchLEDLevels = (int (*)(void *, unsigned int, unsigned int))_PSFindSymbolCallable(hxRef, "__ZN5H9ISP11H9ISPDevice27SetIndividualTorchLEDLevelsEjj");
            break;
        }
        case 6: {
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(hxRef, "__ZL13SetTorchLevelPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, "__ZN5H6ISP26H6ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
            SetTorchColor = (int (*)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchColorPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            SetTorchColorMode = (int (*)(void *, unsigned int, unsigned short, unsigned short))_PSFindSymbolCallable(hxRef, "__ZN5H6ISP11H6ISPDevice17SetTorchColorModeEjtt");
            break;
        }
        default: {
            char SetTorchLevelWithGroupSymbol[88];
            sprintf(SetTorchLevelWithGroupSymbol, "__ZL13SetTorchLevelPKvP19H%dISPCaptureStreamP18H%dISPCaptureGroupP19H%dISPCaptureDevice", HVer, HVer, HVer);
            SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))MSFindSymbol(hxRef, SetTorchLevelWithGroupSymbol);
            if (SetTorchLevelWithGroup == NULL) {
                char SetTorchLevelSymbol[67];
                sprintf(SetTorchLevelSymbol, "__ZL13SetTorchLevelPKvP19H%dISPCaptureStreamP19H%dISPCaptureDevice", HVer, HVer);
                SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(hxRef, SetTorchLevelSymbol);
            }
            char GetCFPreferenceNumberSymbol[60];
            sprintf(GetCFPreferenceNumberSymbol, "__ZN6H%dISP27H%dISPGetCFPreferenceNumberEPK10__CFStringS2_i", HVer, HVer);
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, GetCFPreferenceNumberSymbol);
            char SetIndividualTorchLEDLevelsSymbol[58];
            sprintf(SetIndividualTorchLEDLevelsSymbol, "__ZN6H%dISP12H%dISPDevice27SetIndividualTorchLEDLevelsEjj", HVer, HVer);
            SetIndividualTorchLEDLevels = (int (*)(void *, unsigned int, unsigned int))_PSFindSymbolCallable(hxRef, SetIndividualTorchLEDLevelsSymbol);
            break;
        }
    }
    HBLogDebug(@"SetTorchLevel found: %d", SetTorchLevel != NULL);
    HBLogDebug(@"SetTorchLevelWithGroup found: %d", SetTorchLevelWithGroup != NULL);
    HBLogDebug(@"GetCFPreferenceNumber found: %d", GetCFPreferenceNumber != NULL);
    HBLogDebug(@"SetIndividualTorchLEDLevels found: %d", SetIndividualTorchLEDLevels != NULL);
    if (SetTorchLevelWithGroup) {
        %init(SetTorchLevelWithGroupHook);
    } else {
        %init(SetTorchLevelHook);
    }
    if (SetIndividualTorchLEDLevels != NULL) {
        %init(Quad);
    } else {
        HBLogDebug(@"SetTorchColor found: %d", SetTorchColor != NULL);
        HBLogDebug(@"SetTorchColorMode found: %d", SetTorchColorMode != NULL);
        %init(Dual);
    }
}