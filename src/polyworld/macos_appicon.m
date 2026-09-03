#import <Cocoa/Cocoa.h>

void polyworldSetApplicationIcon(const char *path) {
  if (path == NULL || path[0] == '\0') {
    return;
  }
  @autoreleasepool {
    NSString *nsPath = [NSString stringWithUTF8String:path];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:nsPath];
    if (image != nil) {
      [NSApp setApplicationIconImage:image];
    }
  }
}
