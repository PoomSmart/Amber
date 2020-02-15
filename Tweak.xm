#import "../PS.h"
#import "Header.h"
#import <UIKit/UIColor+Private.h>
#import <UIKit/UIImage+Private.h>

#import <dlfcn.h>
#import <mach/port.h>
#import <mach/kern_return.h>

@interface SBUIFlashlightController : NSObject
+ (instancetype)sharedInstance;
@property(assign) NSUInteger level;
@end

@interface CCUISliderModuleBackgroundViewController : UIViewController
- (void)setGlyphImage:(UIImage *)image;
@end

@interface CCUIFlashlightBackgroundViewController : CCUISliderModuleBackgroundViewController
- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level;
@end

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
    return %orig(arg0, arg1, levels && enabled() ? (both() ? (levels | (levels >> 8)) : (levels >> 8)) : levels);
}

%end

%group SpringBoard_Flashlight

@interface CCUIFlashlightBackgroundViewController (Amber)
- (BOOL)amberActive;
- (BOOL)bothActive;
@end

%hook CCUIFlashlightBackgroundViewController

- (void)viewDidLoad {
    %orig;
    self.view.userInteractionEnabled = YES;
    UISwipeGestureRecognizer *s = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeFlashlightGlyphView:)];
    s.numberOfTouchesRequired = 1;
    s.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:s];
    [s release];
}

%new
- (BOOL)amberActive {
    Boolean keyExist = NO;
    Boolean value = CFPreferencesGetAppBooleanValue(key, kDomain, &keyExist);
    return keyExist ? value : NO;
}

%new
- (BOOL)bothActive {
    Boolean keyExist = NO;
    Boolean value = CFPreferencesGetAppBooleanValue(bothKey, kDomain, &keyExist);
    return keyExist ? value : NO;
}

%new
- (void)swipeFlashlightGlyphView:(id)sender {
    if (![self amberActive]) return;
    NSUInteger level = ((SBUIFlashlightController *)[objc_getClass("SBUIFlashlightController") sharedInstance]).level;
    if (!level) return;
    CFPreferencesSetAppValue(bothKey, [self bothActive] ? kCFBooleanFalse : kCFBooleanTrue, kDomain);
    CFPreferencesAppSynchronize(kDomain);
    [self _updateGlyphForFlashlightLevel:level];
}

- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level {
    NSBundle *bundle = [[[NSBundle bundleForClass:[self class]] retain] autorelease];
    UIImage *image = [[[UIImage imageNamed:level ? @"FlashlightOn" : @"FlashlightOff" inBundle:bundle] retain] autorelease];
    UIColor *flatColor = nil;
    Boolean both_ = [self bothActive];
    if (!level || ![self amberActive])
        flatColor = [[UIColor.whiteColor retain] autorelease];
    else {
        if (both_)
            flatColor = [[[UIColor colorWithRed:1.00 green:0.84 blue:0.59 alpha:1.0] retain] autorelease];
        else
            flatColor = [[UIColor.systemOrangeColor retain] autorelease];
    }
    UIImage *flatImage = [[[image _flatImageWithColor:flatColor] retain] autorelease];
    [self setGlyphImage:flatImage];
}

%end

%end

%group SpringBoard

%hook CCUIModuleCollectionViewController

- (void)_populateModuleViewControllers {
    %orig;
    %init(SpringBoard_Flashlight);
}

%end

%end

%ctor {
    if (IN_SPRINGBOARD) {
        if (isiOS11Up) {
            %init(SpringBoard);
        }
        return;
    }
    int HVer = 0;
    void *IOKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (IOKit) {
        mach_port_t *kIOMasterPortDefault = (mach_port_t *)dlsym(IOKit, "kIOMasterPortDefault");
        CFMutableDictionaryRef (*IOServiceMatching)(const char *name) = (CFMutableDictionaryRef (*)(const char *))dlsym(IOKit, "IOServiceMatching");
        mach_port_t (*IOServiceGetMatchingService)(mach_port_t masterPort, CFDictionaryRef matching) = (mach_port_t (*)(mach_port_t, CFDictionaryRef))dlsym(IOKit, "IOServiceGetMatchingService");
        kern_return_t (*IOObjectRelease)(mach_port_t object) = (kern_return_t (*)(mach_port_t))dlsym(IOKit, "IOObjectRelease");
        if (kIOMasterPortDefault && IOServiceGetMatchingService && IOObjectRelease) {
            mach_port_t h10 = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching("AppleH10CamIn"));
            if (h10) {
                HVer = 10;
                IOObjectRelease(h10);
            }
            if (HVer == 0) {
                mach_port_t h9 = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching("AppleH9CamIn"));
                if (h9) {
                    HVer = 9;
                    IOObjectRelease(h9);
                }
            }
            if (HVer == 0) {
                mach_port_t h6 = IOServiceGetMatchingService(*kIOMasterPortDefault, IOServiceMatching("AppleH6CamIn"));
                if (h6) {
                    HVer = 6;
                    IOObjectRelease(h6);
                }
            }
        }
        dlclose(IOKit);
        HBLogDebug(@"Detected ISP version: %d", HVer);
    }
    if (HVer == 0) return;
    MSImageRef hxRef;
    switch (HVer) {
        case 10:
            dlopen("/System/Library/MediaCapture/H10ISP.mediacapture", RTLD_LAZY);
            hxRef = MSGetImageByName("/System/Library/MediaCapture/H10ISP.mediacapture");
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchLevelPKvP19H10ISPCaptureStreamP19H10ISPCaptureDevice");
            if (SetTorchLevel == NULL)
                SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchLevelPKvP19H10ISPCaptureStreamP18H10ISPCaptureGroupP19H10ISPCaptureDevice");
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, "__ZN6H10ISP27H10ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
            SetIndividualTorchLEDLevels = (int (*)(void *, unsigned int, unsigned int))_PSFindSymbolCallable(hxRef, "__ZN6H10ISP12H10ISPDevice27SetIndividualTorchLEDLevelsEjj");
            break;
        case 9:
            dlopen("/System/Library/MediaCapture/H9ISP.mediacapture", RTLD_LAZY);
            hxRef = MSGetImageByName("/System/Library/MediaCapture/H9ISP.mediacapture");
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP18H9ISPCaptureDevice");
            if (SetTorchLevel == NULL)
                SetTorchLevelWithGroup = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureGroupRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchLevelPKvP18H9ISPCaptureStreamP17H9ISPCaptureGroupP18H9ISPCaptureDevice");
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, "__ZN5H9ISP26H9ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
            SetIndividualTorchLEDLevels = (int (*)(void *, unsigned int, unsigned int))_PSFindSymbolCallable(hxRef, "__ZN5H9ISP11H9ISPDevice27SetIndividualTorchLEDLevelsEjj");
            break;
        case 6:
            dlopen("/System/Library/MediaCapture/H6ISP.mediacapture", RTLD_LAZY);
            hxRef = MSGetImageByName("/System/Library/MediaCapture/H6ISP.mediacapture");
            SetTorchLevel = (int (*)(CFNumberRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchLevelPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            GetCFPreferenceNumber = (SInt32 (*)(CFStringRef const, CFStringRef const, SInt32))_PSFindSymbolCallable(hxRef, "__ZN5H6ISP26H6ISPGetCFPreferenceNumberEPK10__CFStringS2_i");
            SetTorchColor = (int (*)(CFMutableDictionaryRef, HXISPCaptureStreamRef, HXISPCaptureDeviceRef))_PSFindSymbolCallable(hxRef, "__ZL13SetTorchColorPKvP18H6ISPCaptureStreamP18H6ISPCaptureDevice");
            SetTorchColorMode = (int (*)(void *, unsigned int, unsigned short, unsigned short))_PSFindSymbolCallable(hxRef, "__ZN5H6ISP11H6ISPDevice17SetTorchColorModeEjtt");
            break;
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