#import "../Header.h"
#import <UIKit/UIColor+Private.h>
#import <UIKit/UIImage+Private.h>

@interface SBUIFlashlightController : NSObject
+ (instancetype)sharedInstance;
@property (assign) NSUInteger level;
@end

@interface CCUICustomContentModuleBackgroundViewController : UIViewController
- (void)setHeaderTitle:(NSString *)title;
- (void)setHeaderGlyphImage:(UIImage *)image;
- (void)setGlyphImage:(UIImage *)image;
@end

@interface CCUISliderModuleBackgroundViewController : CCUICustomContentModuleBackgroundViewController
@end

@interface CCUIFlashlightBackgroundViewController : CCUISliderModuleBackgroundViewController
- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level;
@end

%group SpringBoard_Flashlight

static NSString *getModeLabel(PSAmberMode mode) {
    switch (mode) {
        case PSAmberModeOrange:
            return @"Amber";
        case PSAmberModeBoth:
            return @"All";
        default:
            return @"Default";
    }
}

BOOL didAddIconGesture = NO;
BOOL didAddLabelGesture = NO;

%hook CCUIFlashlightBackgroundViewController

%new
- (void)tapFlashlightGlyphView:(id)sender {
    NSUInteger level = ((SBUIFlashlightController *)[%c(SBUIFlashlightController) sharedInstance]).level;
    if (!level) return;
    PSAmberMode amberMode = (CFPreferencesGetAppIntegerValue(amberModeKey, kDomain, NULL) + 1) % PSAmberModeCount;
    CFNumberRef numberRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &amberMode);
    CFPreferencesSetAppValue(amberModeKey, numberRef, kDomain);
    CFPreferencesAppSynchronize(kDomain);
    [self _updateGlyphForFlashlightLevel:level];
}

- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *image = [UIImage imageNamed:level ? @"FlashlightOn" : @"FlashlightOff" inBundle:bundle];
    UIColor *flatColor;
    PSAmberMode amberMode = CFPreferencesGetAppIntegerValue(amberModeKey, kDomain, NULL);
    if (!level || amberMode == PSAmberModeDefault)
        flatColor = UIColor.whiteColor;
    else
        flatColor = amberMode == PSAmberModeBoth ? [UIColor colorWithRed:1.00 green:0.84 blue:0.59 alpha:1.0] : UIColor.systemOrangeColor;
    UIImage *flatImage = [image _flatImageWithColor:flatColor];
    if ([self respondsToSelector:@selector(setHeaderGlyphImage:)])
        [self setHeaderGlyphImage:flatImage];
    else
        [self setGlyphImage:flatImage];
    UIImageView *imageView = [self valueForKey:@"_headerImageView"];
    UILabel *titleLabel = [self valueForKey:@"_headerTitleLabel"];
    imageView.tintColor = flatColor;
    imageView.userInteractionEnabled = titleLabel.userInteractionEnabled = level > 0;
    NSString *headerTitle = level ? [NSString stringWithFormat:@"Mode: %@, Tap to change", getModeLabel(amberMode)] : @"";
    [self setHeaderTitle:headerTitle];
    if (level) {
        if (!didAddIconGesture) {
            UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapFlashlightGlyphView:)];
            [imageView addGestureRecognizer:t];
            didAddIconGesture = YES;
        }
        for (UIGestureRecognizer *gesture in titleLabel.gestureRecognizers)
            [titleLabel removeGestureRecognizer:gesture];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapFlashlightGlyphView:)];
        [titleLabel addGestureRecognizer:t];
    }
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
