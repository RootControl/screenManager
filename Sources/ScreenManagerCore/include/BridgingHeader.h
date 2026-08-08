#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

/// Private Accessibility SPI: yields the CGWindowID backing an AXUIElement.
/// Used to match a bound window by stable identity rather than by list index
/// or window title, both of which shift as windows open, close, and rename.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);
