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

@end