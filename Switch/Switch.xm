#import <Flipswitch/FSSwitchDataSource.h>
#import <Flipswitch/FSSwitchPanel.h>
#import "../Header.h"

@interface AmberSwitch : NSObject <FSSwitchDataSource>
@end

@implementation AmberSwitch

- (FSSwitchState)stateForSwitchIdentifier:(NSString *)switchIdentifier {
    Boolean keyExist = NO;
    Boolean enabled = CFPreferencesGetAppBooleanValue(key, kDomain, &keyExist);
    if (!keyExist)
        return FSSwitchStateOff;
    return enabled ? FSSwitchStateOn : FSSwitchStateOff;
}

- (void)applyState:(FSSwitchState)newState forSwitchIdentifier:(NSString *)switchIdentifier {
    if (newState == FSSwitchStateIndeterminate)
        return;
    CFPreferencesSetAppValue(key, newState == FSSwitchStateOn ? kCFBooleanTrue : kCFBooleanFalse, kDomain);
    CFPreferencesAppSynchronize(kDomain);
}

- (BOOL)bothActive {
    Boolean keyExist = NO;
    Boolean value = CFPreferencesGetAppBooleanValue(bothKey, kDomain, &keyExist);
    return keyExist ? value : NO;
}

- (UIColor *)primaryColorForSwitchIdentifier:(NSString *)switchIdentifier {
    if ([self bothActive])
        return [UIColor colorWithRed:1.00 green:0.84 blue:0.59 alpha:1.0];
    return UIColor.systemOrangeColor;
}

- (BOOL)hasAlternateActionForSwitchIdentifier:(NSString *)switchIdentifier {
    return YES;
}

- (void)applyAlternateActionForSwitchIdentifier:(NSString *)switchIdentifier {
    CFPreferencesSetAppValue(bothKey, [self bothActive] ? kCFBooleanFalse : kCFBooleanTrue, kDomain);
    CFPreferencesAppSynchronize(kDomain);
}

@end