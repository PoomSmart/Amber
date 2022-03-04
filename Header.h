#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

CFStringRef const amberModeKey = CFSTR("PSLEDMode");
CFStringRef const kDomain = CFSTR("com.apple.coremedia");

typedef NS_ENUM(int, PSAmberMode) {
    PSAmberModeDefault = 0,
    PSAmberModeOrange,
    PSAmberModeBoth,
    PSAmberModeCount
};