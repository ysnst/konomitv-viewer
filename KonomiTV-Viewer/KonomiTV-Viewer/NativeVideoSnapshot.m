#import "NativeVideoSnapshot.h"
#import <VLCKit/VLCKit.h>
@implementation NativeVideoSnapshot
+ (BOOL)savePlayer:(VLCMediaPlayer *)player toPath:(NSString *)path {
    @try {
        // 両寸法0は再生中の映像フレームの解像度を保つ。操作UIは取得しない。
        [player saveVideoSnapshotAt:path withWidth:0 andHeight:0];
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Video snapshot failed: %@", exception.name);
        return NO;
    }
}
@end
