#import "../Header.h"
#import <UIKit/UIColor+Private.h>
#import <UIKit/UIImage+Private.h>

@interface SBUIFlashlightController : NSObject
+ (instancetype)sharedInstance;
@property (assign) NSUInteger level;
@end

@interface CCUICustomContentModuleBackgroundViewController : UIViewController
- (void)setHeaderGlyphImage:(UIImage *)image;
- (void)setGlyphImage:(UIImage *)image;
@end

@interface CCUISliderModuleBackgroundViewController : CCUICustomContentModuleBackgroundViewController
@end

@interface CCUIFlashlightBackgroundViewController : CCUISliderModuleBackgroundViewController
- (void)_updateGlyphForFlashlightLevel:(NSUInteger)level;
@end

%group SpringBoard_Flashlight

%hook CCUIFlashlightBackgroundViewController

- (void)viewDidLoad {
    %orig;
    // FIXME: This still causes stack overflow on first run
    if (self.viewLoaded) {
        self.view.userInteractionEnabled = YES;
        UISwipeGestureRecognizer *s = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeFlashlightGlyphView:)];
        s.numberOfTouchesRequired = 1;
        s.direction = UISwipeGestureRecognizerDirectionUp;
        [self.view addGestureRecognizer:s];
    }
}

%new
- (void)swipeFlashlightGlyphView:(id)sender {
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
