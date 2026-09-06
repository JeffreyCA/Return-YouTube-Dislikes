#import <UIKit/UIView+Private.h>
#import <YouTubeHeader/_ASCollectionViewCell.h>
#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/ASCollectionView.h>
#import <YouTubeHeader/NSArray+YouTube.h>
#import <YouTubeHeader/ELMCellNode.h>
#import <YouTubeHeader/ELMContainerNode.h>
#import <YouTubeHeader/ELMNodeController.h>
#import <YouTubeHeader/ELMNodeFactory.h>
#import <YouTubeHeader/ELMTextNode.h>
#import <YouTubeHeader/UIView+AsyncDisplayKit.h>
#import <YouTubeHeader/YTAlertView.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTAppViewController.h>
#import <YouTubeHeader/YTAsyncCollectionView.h>
#import <YouTubeHeader/YTColorPalette.h>
#import <YouTubeHeader/YTELMView.h>
#import <YouTubeHeader/YTFullscreenEngagementActionBarButtonRenderer.h>
#import <YouTubeHeader/YTFullscreenEngagementActionBarButtonView.h>
#import <YouTubeHeader/YTIButtonSupportedRenderers.h>
#import <YouTubeHeader/YTIFormattedString.h>
#import <YouTubeHeader/YTILikeButtonRenderer.h>
#import <YouTubeHeader/YTIToggleButtonRenderer.h>
#import <YouTubeHeader/YTPageStyleController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTReelElementAsyncComponentView.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTReelWatchLikesController.h>
#import <YouTubeHeader/YTReelWatchPlaybackOverlayView.h>
#import <YouTubeHeader/YTRollingNumberNode.h>
#import <YouTubeHeader/YTRollingNumberView.h>
#import <YouTubeHeader/YTShortsPlayerViewController.h>
#import <YouTubeHeader/YTWatchController.h>

// Texture layout types that YouTubeHeader does not declare. The encodings
// were verified against YouTube 21.33.6: setHeight:/setMargin: take
// {?=qd}-based structs, setFlexWrap: takes an int, and setAlignItems: takes an
// unsigned char.
typedef NS_ENUM(NSInteger, ASDimensionUnit) {
    ASDimensionUnitAuto,
    ASDimensionUnitPoints,
    ASDimensionUnitFraction,
};

typedef struct {
    ASDimensionUnit unit;
    CGFloat value;
} ASDimension;

typedef struct {
    ASDimension top, left, bottom, right, start, end, horizontal, vertical, all;
} ASEdgeInsets;

typedef NS_ENUM(int, ASStackLayoutFlexWrap) {
    ASStackLayoutFlexWrapNoWrap,
    ASStackLayoutFlexWrapWrap,
};

typedef NS_ENUM(uint8_t, ASStackLayoutAlignItems) {
    ASStackLayoutAlignItemsStart,
    ASStackLayoutAlignItemsEnd,
    ASStackLayoutAlignItemsCenter,
    ASStackLayoutAlignItemsStretch,
    ASStackLayoutAlignItemsBaselineFirst,
    ASStackLayoutAlignItemsBaselineLast,
    ASStackLayoutAlignItemsNotSet,
};

@interface ASLayoutElementStyleYoga (RYDMetadata)
@property (nonatomic, assign) ASDimension height;
@property (nonatomic, assign) ASEdgeInsets margin;
@property (nonatomic, assign) ASStackLayoutFlexWrap flexWrap;
@property (nonatomic, assign) ASStackLayoutAlignItems alignItems;
@end

@interface RYDMetadataState : NSObject
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, copy) NSString *dislikes;
@property (nonatomic, copy) NSString *originalText;
@property (nonatomic, copy) NSString *renderedText;
@property (nonatomic, copy) NSAttributedString *originalAttributedText;
@property (nonatomic, copy) NSAttributedString *tailOriginalAttributedText;
@property (nonatomic, copy) NSAttributedString *tailRenderedAttributedText;
@property (nonatomic, weak) ELMCellNode *cell;
@property (nonatomic, weak) YTRollingNumberNode *likeNode;
@property (nonatomic, weak) ELMTextNode *textNode;
@property (nonatomic, weak) ELMTextNode *tailTextNode;
@property (nonatomic, weak) ASDisplayNode *container;
@property (nonatomic, weak) ASDisplayNode *row;
@property (nonatomic, weak) ASDisplayNode *separatorNode;
@property (nonatomic, weak) ASDisplayNode *tail;
@property (nonatomic, strong) NSMapTable<ASDisplayNode *, NSValue *> *fixedHeights;
@property (nonatomic, assign) ASStackLayoutFlexWrap originalWrap;
@property (nonatomic, assign) ASStackLayoutAlignItems originalAlignItems;
@property (nonatomic, assign) ASEdgeInsets originalSeparatorMargin;
@property (nonatomic, assign) CGFloat originalTailShrink;
@property (nonatomic, assign) NSUInteger originalMaximumNumberOfLines;
@property (nonatomic, assign) BOOL layoutApplied;
@end

@interface ELMCellNode (RYDMetadata)
@property (nonatomic, strong) RYDMetadataState *rydMetadata;
@end

@interface ELMTextNode (RYDMetadata)
@property (nonatomic, strong) RYDMetadataState *rydMetadata;
@property (nonatomic, assign) NSUInteger maximumNumberOfLines;
@end

@interface YTRollingNumberNode (RYD)
@property (strong, nonatomic) NSString *updatedCount;
@property (strong, nonatomic) NSNumber *updatedCountNumber;
@property (strong, nonatomic) RYDMetadataState *rydMetadata;
- (void)updateCount:(NSString *)updateCount color:(UIColor *)color;
@end

@interface YTReelWatchPlaybackOverlayView (RYD)
@property (assign, nonatomic) BOOL didGetVote;
@end
