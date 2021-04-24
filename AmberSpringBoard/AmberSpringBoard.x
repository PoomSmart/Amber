#import "../../PS.h"
#import "../Header.h"
#import <UIKit/UIColor+Private.h>
#import <UIKit/UIImage+Private.h>

@interface SBUIFlashlightController : NSObject
+ (instancetype)sharedInstance;
@property(assign) NSUInteger level;
@end

@interface CCUICustomContentModuleBackgroundViewController : UIViewController
- (void)setHeaderGlyphImage:(UIImage *)image;
@end

@interface CCUISliderModuleBackgroundViewController : CCUICustomContentModuleBackgroundViewController
@end

@interface CCUIFlashlightBackgroundViewController : CCUISliderModuleBackgroundViewController
- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level;
@end

@interface CCUIFlashlightBackgroundViewController (Amber)
- (BOOL)amberActive;
- (BOOL)bothActive;
@end

%group SpringBoard_Flashlight

%hook CCUIFlashlightBackgroundViewController

- (void)viewDidLoad {
    %orig;
    self.view.userInteractionEnabled = YES;
    UISwipeGestureRecognizer *s = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeFlashlightGlyphView:)];
    s.numberOfTouchesRequired = 1;
    s.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:s];
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
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *image = [UIImage imageNamed:level ? @"FlashlightOn" : @"FlashlightOff" inBundle:bundle];
    UIColor *flatColor;
    Boolean both_ = [self bothActive];
    if (!level || ![self amberActive])
        flatColor = UIColor.whiteColor;
    else {
        if (both_)
            flatColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.59 alpha:1.0];
        else
            flatColor = UIColor.systemOrangeColor;
    }
    UIImage *flatImage = [image _flatImageWithColor:flatColor];
    [self setHeaderGlyphImage:flatImage];
    UIImageView *imageView = [self valueForKey:@"_headerImageView"];
    imageView.tintColor = flatColor;
}

%end

%end

%hook CCUIModuleCollectionViewController

- (void)_populateModuleViewControllers {
    %orig;
    %init(SpringBoard_Flashlight);
}

%end

%ctor {
    %init;
}
