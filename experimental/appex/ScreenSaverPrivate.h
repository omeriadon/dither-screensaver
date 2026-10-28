// Private, undocumented declarations recovered from Apple's ScreenSaver bundles.
#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

@interface ScreenSaverExtension : NSObject
@end

@interface ScreenSaverViewController : NSViewController
@end

@interface ScreenSaverConfigurationViewController : NSViewController
- (void)configureSheetWillPresent;
- (void)configureSheetDidEnd;
@end
