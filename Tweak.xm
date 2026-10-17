#import <HBLog.h>
#import <PSHeader/Misc.h>
#import "Header.h"

#import <dlfcn.h>

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

    The levels are represented as a single 32-bit integer. This integer is separated into 8-bit chunks.
    From left to right, the 1st and the 3rd chunks specify the brightness level of the white LEDs (0x00 as min and 0xFF as max).
    Similarly, the 2nd and the 4th chunks specify the brightness level of the amber LEDs (0x00 as min and 0xFF as max).
    Easy enough, having only amber light requires us to set the integer level to be 0x00hh00hh.
    By default, H6ISP and H9ISP cameras ensure that the brightness format is in 0xhh00hh00, locking down any non-jailbroken attempts.
**/

typedef struct HXISPCaptureStream *HXISPCaptureStreamRef;
typedef struct HXISPCaptureDevice *HXISPCaptureDeviceRef;
typedef struct HXISPCaptureGroup *HXISPCaptureGroupRef;

int (*SetTorchLevel)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchLevelWithGroup)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchColor)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchColorWithGroup)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef) = NULL;
int (*SetTorchColorMode)(void *, unsigned int, unsigned short, unsigned short) = NULL;
SInt32 (*GetCFPreferenceNumber)(CFStringRef const, CFStringRef const, SInt32) = NULL;

int (*SetIndividualTorchLEDLevels16)(void *, unsigned int, unsigned int) = NULL;
int (*SetIndividualTorchLEDLevels13)(void *, unsigned int, unsigned int) = NULL;
int (*SetIndividualTorchLEDLevels10)(void *, unsigned int, unsigned int) = NULL;
int (*SetIndividualTorchLEDLevels9)(void *, unsigned int, unsigned int) = NULL;

static SInt32 amberMode() {
    return GetCFPreferenceNumber(amberModeKey, kDomain, PSAmberModeDefault);
}

static unsigned int adjustedIndividualTorchLEDLevels(unsigned int levels) {
    // both: 0xhh00hh00 -> 0xhhhhhhhh
    // amber only: 0xhh00hh00 -> 0x00hh00hh
    PSAmberMode mode = (PSAmberMode)amberMode();
    return levels && mode ? (mode == PSAmberModeBoth ? (levels | (levels >> 8)) : (levels >> 8)) : levels;
}

static void SetTorchLevelHook(int result, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureGroupRef group, HXISPCaptureDeviceRef device) {
    if (!result && level && amberMode()) {
        // If torch level setting is successful, we can override the torch color
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        int val = 100; // from 0 (coolest) to 100 (warmest)
        CFNumberRef threshold = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &val);
        CFDictionaryAddValue(dict, CFSTR("WarmLEDPercentile"), threshold);
        // Now tell the camera the "fake" scene condition
        if (SetTorchColorWithGroup)
            SetTorchColorWithGroup(dict, stream, group, device);
        else
            SetTorchColor(dict, stream, device);
        CFRelease(threshold);
        CFRelease(dict);
    }
}

%group SetTorchLevelHook

%hookf(int, SetTorchLevel, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureDeviceRef device) {
    int result = %orig(level, stream, device);
    SetTorchLevelHook(result, level, stream, NULL, device);
    return result;
}

%end

%group SetTorchLevelWithGroupHook

%hookf(int, SetTorchLevelWithGroup, CFNumberRef level, HXISPCaptureStreamRef stream, HXISPCaptureGroupRef group, HXISPCaptureDeviceRef device) {
    int result = %orig(level, stream, group, device);
    SetTorchLevelHook(result, level, stream, group, device);
    return result;
}

%end

%group Dual

%hookf(int, SetTorchColorMode, void *arg0, unsigned int arg1, unsigned short mode, unsigned short level) {
    return %orig(arg0, arg1, amberMode() == PSAmberModeBoth ? 1 : mode, level);
}

%end

%group Quad16

%hookf(int, SetIndividualTorchLEDLevels16, void *arg0, unsigned int arg1, unsigned int levels) {
    return %orig(arg0, arg1, adjustedIndividualTorchLEDLevels(levels));
}

%end

%group Quad13

%hookf(int, SetIndividualTorchLEDLevels13, void *arg0, unsigned int arg1, unsigned int levels) {
    return %orig(arg0, arg1, adjustedIndividualTorchLEDLevels(levels));
}

%end

%group Quad10

%hookf(int, SetIndividualTorchLEDLevels10, void *arg0, unsigned int arg1, unsigned int levels) {
    return %orig(arg0, arg1, adjustedIndividualTorchLEDLevels(levels));
}

%end

%group Quad9

%hookf(int, SetIndividualTorchLEDLevels9, void *arg0, unsigned int arg1, unsigned int levels) {
    return %orig(arg0, arg1, adjustedIndividualTorchLEDLevels(levels));
}

%end

static MSImageRef openISP(int ver) {
    char imagePath[49];
    snprintf(imagePath, sizeof(imagePath), "/System/Library/MediaCapture/H%dISP.mediacapture", ver);
    dlopen(imagePath, RTLD_NOW);
    return MSGetImageByName(imagePath);
}

static void bindPreference(MSImageRef image, int ver) {
    if (GetCFPreferenceNumber || !image) return;
    if (ver == 9) {
        GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(image, "__ZN5H9ISP26H9ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
    } else if (ver == 6) {
        GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(image, "__ZN5H6ISP26H6ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
    } else {
        char symbol[80];
        snprintf(symbol, sizeof(symbol), "__ZN6H%dISP27H%dISPGetCFPreferenceNumberEPK10__CFStringS2_i", ver, ver);
        GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(image, symbol);
    }
}

static void *findIndividualTorchLEDLevels(MSImageRef image, int ver) {
    if (!image || ver == 6) return NULL;
    if (ver == 9)
        return MSFindSymbol(image, "__ZN5H9ISP11H9ISPDevice27SetIndividualTorchLEDLevelsEjj");
    char symbol[64];
    snprintf(symbol, sizeof(symbol), "__ZN6H%dISP12H%dISPDevice27SetIndividualTorchLEDLevelsEjj", ver, ver);
    return MSFindSymbol(image, symbol);
}

%ctor {
    int hvers[] = { 16, 13, 10, 9, 6 };
    BOOL hookedQuad = NO;
    int dualVer = 0;
    MSImageRef dualRef = NULL;
    for (int i = 0; i < (int)(sizeof(hvers) / sizeof(hvers[0])); ++i) {
        int ver = hvers[i];
        MSImageRef image = openISP(ver);
        if (!image) continue;
        void *quad = findIndividualTorchLEDLevels(image, ver);
        if (quad) {
            bindPreference(image, ver);
            if (ver == 16) {
                SetIndividualTorchLEDLevels16 = (int (*)(void *, unsigned int, unsigned int))quad;
                %init(Quad16);
            } else if (ver == 13) {
                SetIndividualTorchLEDLevels13 = (int (*)(void *, unsigned int, unsigned int))quad;
                %init(Quad13);
            } else if (ver == 10) {
                SetIndividualTorchLEDLevels10 = (int (*)(void *, unsigned int, unsigned int))quad;
                %init(Quad10);
            } else if (ver == 9) {
                SetIndividualTorchLEDLevels9 = (int (*)(void *, unsigned int, unsigned int))quad;
                %init(Quad9);
            }
            hookedQuad = YES;
            HBLogDebug(@"Hooked SetIndividualTorchLEDLevels in H%dISP", ver);
            continue;
        }
        if (!dualRef) {
            dualVer = ver;
            dualRef = image;
        }
    }
    if (hookedQuad || !dualRef) return;
    HBLogDebug(@"Using dual-LED path for H%dISP", dualVer);
    switch (dualVer) {
        case 9: {
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(dualRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP18H9ISPCaptureDevice");
            if (SetTorchLevel == NULL)
                SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))MSFindSymbol(dualRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP17H9ISPCaptureGroupP18H9ISPCaptureDevice");
            bindPreference(dualRef, dualVer);
            break;
        }
        case 6: {
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(dualRef, "__ZL13SetTorchLevelPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            bindPreference(dualRef, dualVer);
            SetTorchColor = (int (*)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(dualRef, "__ZL13SetTorchColorPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            SetTorchColorMode = (int (*)(void *, unsigned int, unsigned short, unsigned short))MSFindSymbol(dualRef, "__ZN5H6ISP11H6ISPDevice17SetTorchColorModeEjtt");
            break;
        }
        default: {
            char SetTorchLevelWithGroupSymbol[96];
            snprintf(SetTorchLevelWithGroupSymbol, sizeof(SetTorchLevelWithGroupSymbol), "__ZL13SetTorchLevelPKvP19H%dISPCaptureStreamP18H%dISPCaptureGroupP19H%dISPCaptureDevice", dualVer, dualVer, dualVer);
            SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))MSFindSymbol(dualRef, SetTorchLevelWithGroupSymbol);
            if (SetTorchLevelWithGroup == NULL) {
                char SetTorchLevelSymbol[80];
                snprintf(SetTorchLevelSymbol, sizeof(SetTorchLevelSymbol), "__ZL13SetTorchLevelPKvP19H%dISPCaptureStreamP19H%dISPCaptureDevice", dualVer, dualVer);
                SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))MSFindSymbol(dualRef, SetTorchLevelSymbol);
            }
            bindPreference(dualRef, dualVer);
            char SetTorchColorWithGroupSymbol[96];
            snprintf(SetTorchColorWithGroupSymbol, sizeof(SetTorchColorWithGroupSymbol), "__ZL13SetTorchColorPKvP19H%dISPCaptureStreamP18H%dISPCaptureGroupP19H%dISPCaptureDevice", dualVer, dualVer, dualVer);
            SetTorchColorWithGroup = (int (*)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(dualRef, SetTorchColorWithGroupSymbol);
            char SetTorchColorModeSymbol[64];
            snprintf(SetTorchColorModeSymbol, sizeof(SetTorchColorModeSymbol), "__ZN6H%dISP12H%dISPDevice17SetTorchColorModeEjtt", dualVer, dualVer);
            SetTorchColorMode = (int (*)(void *, unsigned int, unsigned short, unsigned short))MSFindSymbol(dualRef, SetTorchColorModeSymbol);
            break;
        }
    }
    HBLogDebug(@"SetTorchLevel found: %d", SetTorchLevel != NULL);
    HBLogDebug(@"SetTorchLevelWithGroup found: %d", SetTorchLevelWithGroup != NULL);
    HBLogDebug(@"GetCFPreferenceNumber found: %d", GetCFPreferenceNumber != NULL);
    if (SetTorchLevelWithGroup) {
        %init(SetTorchLevelWithGroupHook);
    } else {
        %init(SetTorchLevelHook);
    }
    HBLogDebug(@"SetTorchColor found: %d", SetTorchColor != NULL);
    HBLogDebug(@"SetTorchColorWithGroup found: %d", SetTorchColorWithGroup != NULL);
    HBLogDebug(@"SetTorchColorMode found: %d", SetTorchColorMode != NULL);
    %init(Dual);
}
