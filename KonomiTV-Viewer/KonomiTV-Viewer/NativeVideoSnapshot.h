#import <Foundation/Foundation.h>
@class VLCMediaPlayer;
NS_ASSUME_NONNULL_BEGIN
// 配布SDKのSwift名に依存せず、4系の公開Objective-C selectorへ接続する。
FOUNDATION_EXPORT BOOL KonomiTVConfigureRepeat(VLCMediaPlayer *player, BOOL enabled);
/// SwiftへNSExceptionを伝播させず、映像取得の失敗として返す。
@interface NativeVideoSnapshot : NSObject
+ (BOOL)savePlayer:(VLCMediaPlayer *)player toPath:(NSString *)path NS_SWIFT_NAME(save(player:path:));
@end
NS_ASSUME_NONNULL_END
