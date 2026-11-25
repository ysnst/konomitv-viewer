#import <Foundation/Foundation.h>
@class VLCMediaPlayer;
NS_ASSUME_NONNULL_BEGIN
/// SwiftへNSExceptionを伝播させず、映像取得の失敗として返す。
@interface NativeVideoSnapshot : NSObject
+ (BOOL)savePlayer:(VLCMediaPlayer *)player toPath:(NSString *)path NS_SWIFT_NAME(save(player:path:));
@end
NS_ASSUME_NONNULL_END
