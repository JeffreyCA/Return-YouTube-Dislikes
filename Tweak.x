#import <HBLog.h>
#import <UIKit/UIKit.h>
#import "API.h"
#import "Settings.h"
#import "Shared.h"
#import "Tweak.h"
#import "TweakSettings.h"
#import "Vote.h"

@interface ASCollectionView (RYD)
@property (nonatomic, assign) BOOL hasDislikeIntent;
@property (nonatomic, assign) BOOL isProbablyVideoDescriptionHeaderPanel;
@end

static NSCache <NSString *, NSDictionary *> *cache;
NSString *localizedDislikeText = nil;

extern NSBundle *RYDBundle();

@implementation RYDMetadataState
@end

%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(YTILikeButtonRenderer *)renderer {
    %orig;
    if (!TweakEnabled()) return;
    YTQTMButton *dislikeButton = self.dislikeButton;
    [dislikeButton setTitle:FETCHING forState:UIControlStateNormal];
    [dislikeButton setTitle:FETCHING forState:UIControlStateSelected];
    YTLikeStatus likeStatus = renderer.likeStatus;
    getVoteFromVideoWithHandler(cache, renderer.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        NSString *formattedDislikeCount = getNormalizedDislikes(getDislikeData(data), error);
        NSString *formattedToggledDislikeCount = getNormalizedDislikes(@([getDislikeData(data) unsignedIntegerValue] + 1), error);
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedDislikeCount];
        YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledDislikeCount];
        if (renderer.hasDislikeCountText)
            renderer.dislikeCountText = formattedText;
        if (renderer.hasDislikeCountWithDislikeText)
            renderer.dislikeCountWithDislikeText = formattedToggledText;
        if (renderer.hasDislikeCountWithUndislikeText)
            renderer.dislikeCountWithUndislikeText = formattedText;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (likeStatus == YTLikeStatusDislike) {
                [dislikeButton setTitle:[renderer.dislikeCountWithUndislikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
            } else {
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountWithDislikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
            }
        });
        if ((ExactLikeNumber() || UseRYDLikeData()) && error == nil) {
            YTQTMButton *likeButton = self.likeButton;
            NSString *formattedLikeCount = getNormalizedLikes(getLikeData(data), nil);
            NSString *formattedToggledLikeCount = getNormalizedDislikes(@([getLikeData(data) unsignedIntegerValue] + 1), nil);
            YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedLikeCount];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledLikeCount];
            if (renderer.hasLikeCountText)
                renderer.likeCountText = formattedText;
            if (renderer.hasLikeCountWithLikeText)
                renderer.likeCountWithLikeText = formattedToggledText;
            if (renderer.hasLikeCountWithUnlikeText)
                renderer.likeCountWithUnlikeText = formattedText;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (likeStatus == YTLikeStatusLike) {
                    [likeButton setTitle:[renderer.likeCountWithUnlikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [likeButton setTitle:[renderer.likeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
                } else {
                    [likeButton setTitle:[renderer.likeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [likeButton setTitle:[renderer.likeCountWithLikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
                }
            });
        }
    });
}

%end

%hook YTLikeService

- (void)notifyVideoLikeStatus:(YTLikeStatus)likeStatus withID:(NSString *)videoId {
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(videoId, likeStatus);
    %orig;
}

- (void)notifyPlaylistLikeStatus:(YTLikeStatus)likeStatus withID:(NSString *)playlistId {
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(playlistId, likeStatus);
    %orig;
}

%end

%hook YTLikeServiceImpl

- (void)notifyVideoLikeStatus:(YTLikeStatus)likeStatus withID:(NSString *)videoId {
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(videoId, likeStatus);
    %orig;
}

- (void)notifyPlaylistLikeStatus:(YTLikeStatus)likeStatus withID:(NSString *)playlistId {
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(playlistId, likeStatus);
    %orig;
}

%end

int overrideNodeCreation = 0;

static NSString *getElementDescription(ELMCellNode *node) {
    HBLogDebug(@"RYD: Found node: %@", node);
    if (![node isKindOfClass:%c(ELMCellNode)]) return nil;
    ELMNodeController *controller = [node controller];
    HBLogDebug(@"RYD: Found controller: %@", controller);
    return [[controller owningComponent] description];
}

static BOOL isVideoScrollableActionBar(ASCollectionView *collectionView, ELMCellNode *node) {
    return [collectionView.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"];
}

static BOOL isVideoDescriptionHeader(ASCollectionView *collectionView, ELMCellNode *node) {
    return [getElementDescription(node) containsString:@"video_description_header.eml"];
}

__strong ELMTextNode *likeTextNode = nil;
__strong YTRollingNumberNode *likeRollingNumberNode = nil;
__strong ELMTextNode *dislikeTextNode = nil;
__strong YTRollingNumberNode *dislikeRollingNumberNode = nil;

__strong ELMTextNode *infoLikeTextNode = nil;
__strong YTRollingNumberNode *infoLikeRollingNumberNode = nil;
__strong YTRollingNumberNode *infoDislikeRollingNumberNode = nil;

__strong NSMutableAttributedString *mutableDislikeText = nil;

static NSString *getVideoId(ASDisplayNode *containerNode) {
    UIViewController *vc = [containerNode closestViewController];
    for (UIViewController *parent = vc; parent; parent = parent.parentViewController) {
        if ([parent isKindOfClass:%c(YTWatchViewController)]) {
            NSString *videoID = [parent valueForKey:@"_videoID"];
            if (videoID.length) return videoID;
        }
    }
    if (![vc isKindOfClass:%c(YTWatchNextResultsViewController)]) return nil;
    YTPlayerViewController *pvc;
    NSObject *wc;
    @try {
        wc = [vc valueForKey:@"_metadataPanelStateProvider"];
    } @catch (id ex) {
        wc = [vc valueForKey:@"_ngwMetadataPanelStateProvider"];
    }
    @try {
        YTWatchPlaybackController *wpc = ((YTWatchController *)wc).watchPlaybackController;
        pvc = [wpc valueForKey:@"_playerViewController"];
    } @catch (id ex) {
        pvc = [wc valueForKey:@"_playerViewController"];
    }
    return [pvc contentVideoID];
}

static void getVoteAndModifyButtons(
    NSString *videoId,
    int pairMode,
    void (^likeHandler)(NSString *likeCount, NSNumber *likeNumber),
    void (^dislikeHandler)(NSString *dislikeCount, NSNumber *dislikeNumber)
) {
    getVoteFromVideoWithHandler(cache, videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        HBLogDebug(@"RYD: Vote data for video %@: %@", videoId, data);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ((ExactLikeNumber() || UseRYDLikeData()) && error == nil) {
                NSNumber *likeNumber = getLikeData(data);
                NSString *likeCount = getNormalizedLikes(likeNumber, nil);
                if (likeCount && likeHandler) {
                    HBLogDebug(@"RYD: Set like count for %@ to %@", videoId, likeCount);
                    likeHandler(likeCount, likeNumber);
                }
            }
            NSNumber *dislikeNumber = getDislikeData(data);
            NSString *dislikeCount = getNormalizedDislikes(dislikeNumber, error);
            if (dislikeHandler) {
                HBLogDebug(@"RYD: Set dislike count for %@ to %@", videoId, dislikeCount);
                dislikeHandler(dislikeCount, dislikeNumber);
            }
        });
    });
}

static void setRollingNumberText(YTRollingNumberView *view, NSString *text, NSNumber *number, UIColor *color) {
    color = color ?: view.color;
    if ([view respondsToSelector:@selector(setUpdatedCount:updatedCountNumber:font:fontAttributes:color:skipAnimation:)])
        [view setUpdatedCount:text updatedCountNumber:number font:view.font fontAttributes:view.fontAttributes color:color skipAnimation:YES];
    else
        [view setUpdatedCount:text updatedCountNumber:number font:view.font color:color skipAnimation:YES];
}

static NSString *metadataDislikeText(RYDMetadataState *state) {
    NSString *format = [RYDBundle() localizedStringForKey:@"DISLIKES_COUNT_FORMAT"
        value:[NSString stringWithFormat:@"%%@ %@", localizedDislikeText] table:nil];
    return [NSString stringWithFormat:format, state.dislikes];
}

static void updateMetadataRollingNumber(YTRollingNumberNode *node) {
    RYDMetadataState *state = node.rydMetadata;
    if (!state) return;
    YTRollingNumberView *view = [node valueForKey:@"_rollingNumberView"];
    if (![view.updatedCount isEqualToString:state.renderedText])
        state.originalText = view.updatedCount;
    if (!TweakEnabled() || !state.dislikes) {
        if ([view.updatedCount isEqualToString:state.renderedText])
            setRollingNumberText(view, state.originalText, view.updatedCountNumber, nil);
        state.renderedText = nil;
        return;
    }
    if (!state.originalText.length) return;
    // Native statistics are separated by two spaces, so match that instead of a dot.
    state.renderedText = [NSString stringWithFormat:@"%@  %@", state.originalText, metadataDislikeText(state)];
    // The native update reuses digit views from the right and may still be
    // rolling the trailing digits toward the like count. Drop those views first
    // so the appended dislike digits cannot finish someone else's animation.
    setRollingNumberText(view, @"", view.updatedCountNumber, nil);
    setRollingNumberText(view, state.renderedText, view.updatedCountNumber, nil);
}

static void updateMetadataTextNode(ELMTextNode *node) {
    RYDMetadataState *state = node.rydMetadata;
    if (!state || state.textNode != node) return;
    if (![node.attributedText.string isEqualToString:state.renderedText])
        state.originalAttributedText = node.attributedText;
    if (!TweakEnabled() || !state.dislikes) {
        if ([node.attributedText.string isEqualToString:state.renderedText])
            node.attributedText = state.originalAttributedText;
        state.renderedText = nil;
        return;
    }
    NSAttributedString *original = state.originalAttributedText;
    NSRange separator = [original.string rangeOfString:@"\\s{2,}" options:NSRegularExpressionSearch];
    if (!original.length || separator.location == NSNotFound || separator.location == 0) {
        HBLogDebug(@"RYD: Unsupported metadata text separators");
        return;
    }
    NSMutableAttributedString *updated = original.mutableCopy;
    // Keep each statistic together while allowing breaks at the field separators.
    for (NSUInteger index = 1; index + 1 < original.length; index++) {
        if ([original.string characterAtIndex:index] == ' ' &&
            [original.string characterAtIndex:index - 1] != ' ' &&
            [original.string characterAtIndex:index + 1] != ' ')
            [updated replaceCharactersInRange:NSMakeRange(index, 1) withString:@" "];
    }
    NSDictionary *attributes = [original attributesAtIndex:separator.location - 1 effectiveRange:nil];
    NSString *countText = [metadataDislikeText(state) stringByReplacingOccurrencesOfString:@" " withString:@" "];
    NSAttributedString *dislikes = [[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"  %@", countText] attributes:attributes];
    [updated insertAttributedString:dislikes atIndex:separator.location];
    state.renderedText = updated.string;
    node.attributedText = updated;
}

static NSRange metadataLeadingWhitespace(NSAttributedString *text) {
    return [text.string rangeOfString:@"^\\s+" options:NSRegularExpressionSearch];
}

// The age/"...more" text starts with the whitespace that separates it from the
// views counter. That whitespace becomes an end margin on the counter instead
// (see applyMetadataLayout), so a wrapped line starts flush with the likes.
static void updateMetadataTail(ELMTextNode *node) {
    RYDMetadataState *state = node.rydMetadata;
    if (!state || state.tailTextNode != node) return;
    if (![node.attributedText isEqualToAttributedString:state.tailRenderedAttributedText])
        state.tailOriginalAttributedText = node.attributedText;
    if (!TweakEnabled() || !state.dislikes) {
        if ([node.attributedText isEqualToAttributedString:state.tailRenderedAttributedText])
            node.attributedText = state.tailOriginalAttributedText;
        state.tailRenderedAttributedText = nil;
        return;
    }
    NSMutableAttributedString *text = state.tailOriginalAttributedText.mutableCopy;
    NSRange leading = metadataLeadingWhitespace(text);
    if (!text || leading.location == NSNotFound) return;
    [text deleteCharactersInRange:leading];
    state.tailRenderedAttributedText = text;
    if (![node.attributedText isEqualToAttributedString:text])
        node.attributedText = text;
}

static CGFloat metadataSeparatorWidth(RYDMetadataState *state) {
    NSAttributedString *text = state.tailOriginalAttributedText ?: state.tailTextNode.attributedText;
    NSRange leading = metadataLeadingWhitespace(text);
    if (leading.location == NSNotFound) return 0;
    return ceil([[text attributedSubstringFromRange:leading] size].width);
}

static ASDisplayNode *metadataCounterNode(ASDisplayNode *node) {
    NSArray<ASDisplayNode *> *children = node.yogaChildren;
    // This metadata component groups the likes counter, views counter, and age/more text.
    if (children.count == 3 &&
        [children[0] isKindOfClass:%c(YTRollingNumberNode)] &&
        [children[1] isKindOfClass:%c(YTRollingNumberNode)] &&
        [children[2] isKindOfClass:%c(ELMContainerNode)])
        return children[0];
    // Non-live statistics use a single styled text node after the channel handle.
    if (children.count == 2 &&
        [children[0] isKindOfClass:%c(ELMTextNode)] &&
        [children[1] isKindOfClass:%c(ELMTextNode)])
        return children[1];
    for (ASDisplayNode *child in children) {
        ASDisplayNode *counter = metadataCounterNode(child);
        if (counter) return counter;
    }
    return nil;
}

// The template pins the statistics rows to a fixed 16-point height and centers
// the channel handle in them. Letting those rows size to their content is what
// makes the cell measure tall enough for a second line; the collection view
// then picks the new height up through the node's own layout.
static void applyMetadataLayout(RYDMetadataState *state) {
    if (state.layoutApplied) return;
    state.layoutApplied = YES;
    state.fixedHeights = [NSMapTable weakToStrongObjectsMapTable];
    for (ASDisplayNode *node = state.container; node && node != state.cell; node = node.yogaParent) {
        ASDimension height = node.style.height;
        if (height.unit == ASDimensionUnitAuto) continue;
        [state.fixedHeights setObject:[NSValue valueWithBytes:&height objCType:@encode(ASDimension)] forKey:node];
        node.style.height = (ASDimension){ASDimensionUnitAuto, 0};
    }
    state.originalAlignItems = state.row.style.alignItems;
    state.row.style.alignItems = ASStackLayoutAlignItemsStart;
    state.originalWrap = state.container.style.flexWrap;
    state.originalTailShrink = state.tail.style.flexShrink;
    state.originalSeparatorMargin = state.separatorNode.style.margin;
    if (state.likeNode) {
        state.container.style.flexWrap = ASStackLayoutFlexWrapWrap;
        state.tail.style.flexShrink = 0;
        CGFloat separator = metadataSeparatorWidth(state);
        if (separator > 0) {
            ASEdgeInsets margin = state.originalSeparatorMargin;
            margin.end = (ASDimension){ASDimensionUnitPoints, separator};
            state.separatorNode.style.margin = margin;
        }
    }
}

static void restoreMetadataLayout(RYDMetadataState *state) {
    if (!state.layoutApplied) return;
    state.layoutApplied = NO;
    for (ASDisplayNode *node in state.fixedHeights) {
        ASDimension height;
        [[state.fixedHeights objectForKey:node] getValue:&height];
        node.style.height = height;
    }
    state.fixedHeights = nil;
    state.row.style.alignItems = state.originalAlignItems;
    state.container.style.flexWrap = state.originalWrap;
    state.tail.style.flexShrink = state.originalTailShrink;
    state.separatorNode.style.margin = state.originalSeparatorMargin;
}

static void restoreMetadataState(RYDMetadataState *state) {
    restoreMetadataLayout(state);
    state.dislikes = nil;
    updateMetadataRollingNumber(state.likeNode);
    state.likeNode.rydMetadata = nil;
    updateMetadataTail(state.tailTextNode);
    state.tailTextNode.rydMetadata = nil;
    if (state.textNode) {
        state.textNode.maximumNumberOfLines = state.originalMaximumNumberOfLines;
        updateMetadataTextNode(state.textNode);
        state.textNode.rydMetadata = nil;
    }
    [state.cell setNeedsLayout];
}

static void configureMetadataCount(ELMCellNode *cell) {
    RYDMetadataState *previous = cell.rydMetadata;
    if (!TweakEnabled()) {
        if (previous) {
            restoreMetadataState(previous);
            cell.rydMetadata = nil;
        }
        return;
    }
    ASDisplayNode *counter = metadataCounterNode(cell);
    if (!counter) {
        HBLogDebug(@"RYD: Unsupported video metadata counter layout");
        return;
    }
    NSString *videoID = getVideoId(cell);
    if (!videoID.length) {
        HBLogDebug(@"RYD: Video metadata has no active video ID yet");
        return;
    }
    if ([previous.videoID isEqualToString:videoID] &&
        (previous.likeNode == counter || previous.textNode == counter)) return;
    if (previous) restoreMetadataState(previous);
    RYDMetadataState *state = [RYDMetadataState new];
    state.videoID = videoID;
    state.cell = cell;
    state.container = counter.yogaParent;
    cell.rydMetadata = state;
    if ([counter isKindOfClass:%c(YTRollingNumberNode)]) {
        NSArray<ASDisplayNode *> *siblings = state.container.yogaChildren;
        state.likeNode = (YTRollingNumberNode *)counter;
        state.likeNode.rydMetadata = state;
        state.row = state.container.yogaParent;
        state.separatorNode = siblings[siblings.count - 2];
        state.tail = siblings.lastObject;
        ASDisplayNode *tailText = state.tail.yogaChildren.firstObject;
        if ([tailText isKindOfClass:%c(ELMTextNode)]) {
            state.tailTextNode = (ELMTextNode *)tailText;
            state.tailTextNode.rydMetadata = state;
        }
    } else {
        state.textNode = (ELMTextNode *)counter;
        state.row = state.container;
        state.originalMaximumNumberOfLines = state.textNode.maximumNumberOfLines;
        state.textNode.rydMetadata = state;
    }
    __weak ELMCellNode *weakCell = cell;
    getVoteFromVideoWithHandler(cache, videoID, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ELMCellNode *currentCell = weakCell;
            if (!currentCell || currentCell.rydMetadata != state || !TweakEnabled() ||
                ![getVideoId(currentCell) isEqualToString:videoID]) return;
            NSNumber *number = getDislikeData(data);
            if (error || ![number isKindOfClass:NSNumber.class]) {
                HBLogDebug(@"RYD: Could not load metadata dislikes for %@: %@", videoID, error ?: @"missing count");
                return;
            }
            state.dislikes = getNormalizedDislikes(number, nil);
            updateMetadataTail(state.tailTextNode);
            applyMetadataLayout(state);
            if (state.likeNode) {
                updateMetadataRollingNumber(state.likeNode);
                [state.likeNode relayoutNode];
            } else {
                state.textNode.maximumNumberOfLines = 2;
                updateMetadataTextNode(state.textNode);
                [state.textNode setNeedsLayout];
            }
            [currentCell setNeedsLayout];
        });
    });
}

static void configureVisibleMetadataCell(ELMCellNode *cell) {
    if (![[[cell.controller owningComponent] templateURI] hasPrefix:@"video_metadata_inner.eml"]) return;
    __weak ELMCellNode *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        ELMCellNode *currentCell = weakCell;
        if (currentCell.isNodeLoaded && currentCell.view.window)
            configureMetadataCount(currentCell);
    });
}

static YTCommonColorPalette *currentColorPalette() {
    Class YTPageStyleControllerClass = %c(YTPageStyleController);
    if (YTPageStyleControllerClass)
        return [YTPageStyleControllerClass currentColorPalette];
    YTAppDelegate *delegate = (YTAppDelegate *)[UIApplication sharedApplication].delegate;
    YTAppViewController *appViewController = [delegate valueForKey:@"_appViewController"];
    NSInteger pageStyle = [appViewController pageStyle];
    Class YTCommonColorPaletteClass = %c(YTCommonColorPalette);
    if (YTCommonColorPaletteClass)
        return pageStyle == 1 ? [YTCommonColorPaletteClass darkPalette] : [YTCommonColorPaletteClass lightPalette];
    return [%c(YTColorPalette) colorPaletteForPageStyle:pageStyle];
}

static void setTextColor(NSMutableAttributedString *text) {
    if (text == nil) return;
    UIColor *color = [currentColorPalette() textPrimary];
    [text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, text.length)];
}

%hook ASCollectionView

%property (nonatomic, assign) BOOL hasDislikeIntent;
%property (nonatomic, assign) BOOL isProbablyVideoDescriptionHeaderPanel;

- (void)didMoveToWindow {
    %orig;
    if (self.window)
        self.isProbablyVideoDescriptionHeaderPanel = [[self _viewControllerForAncestor].navigationController isKindOfClass:%c(YTEngagementPanelNavigationController)];
}

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    ELMCellNode *node = %orig;
    if ([node isKindOfClass:%c(ELMCellNode)] &&
        [[[node.controller owningComponent] templateURI] hasPrefix:@"video_metadata_inner.eml"]) {
        configureMetadataCount(node);
        return node;
    }
    if (!TweakEnabled()) return node;
    if (self.isProbablyVideoDescriptionHeaderPanel && isVideoDescriptionHeader(self, node)) {
        NSString *videoId = getVideoId(node);
        if (videoId == nil) return node;
        HBLogDebug(@"RYD: Found video description header");
        ELMContainerNode *rootContainerNode = [node.yogaChildren firstObject];
        ELMContainerNode *mainContainerNode = rootContainerNode.yogaChildren[1];
        ELMContainerNode *likeContainerNode = [mainContainerNode.yogaChildren firstObject];
        ELMContainerNode *rollingNumberContainerNode = [likeContainerNode.yogaChildren firstObject];

        if (rollingNumberContainerNode.yogaChildren.count == 1) {
            HBLogDebug(@"RYD: Appending dislike number to existing like number");
            infoLikeRollingNumberNode = [rollingNumberContainerNode.yogaChildren firstObject];
            id elementContext = [infoLikeRollingNumberNode valueForKey:@"_context"];
            overrideNodeCreation = 1;
            infoDislikeRollingNumberNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:infoLikeRollingNumberNode.element materializationContext:&elementContext];
            overrideNodeCreation = 0;
            infoDislikeRollingNumberNode.updatedCount = FETCHING;
            infoDislikeRollingNumberNode.updatedCountNumber = @(0);
            [infoDislikeRollingNumberNode updateRollingNumberView];
            [rollingNumberContainerNode addYogaChild:infoDislikeRollingNumberNode];
            [rollingNumberContainerNode.view addSubview:infoDislikeRollingNumberNode.view];

            self.hasDislikeIntent = YES;
            getVoteAndModifyButtons(
                videoId,
                -1,
                ^(NSString *likeCount, NSNumber *likeNumber) {
                    infoLikeRollingNumberNode.updatedCount = likeCount;
                    infoLikeRollingNumberNode.updatedCountNumber = likeNumber;
                    [infoLikeRollingNumberNode updateRollingNumberView];
                    [infoLikeRollingNumberNode relayoutNode];
                },
                ^(NSString *dislikeCount, NSNumber *dislikeNumber) {
                    infoDislikeRollingNumberNode.updatedCount = [NSString stringWithFormat:@"• %@", dislikeCount];
                    infoDislikeRollingNumberNode.updatedCountNumber = dislikeNumber;
                    [infoDislikeRollingNumberNode updateRollingNumberView];
                    [infoDislikeRollingNumberNode relayoutNode];
                }
            );
        }

        infoLikeTextNode = likeContainerNode.yogaChildren[1];
        if (![infoLikeTextNode.attributedText.string containsString:@"•"]) {
            NSMutableAttributedString *likeText = [[NSMutableAttributedString alloc] initWithAttributedString:infoLikeTextNode.attributedText]; 
            likeText.mutableString.string = [likeText.string stringByAppendingString:[NSString stringWithFormat:@" • %@", localizedDislikeText]];
            infoLikeTextNode.attributedText = likeText;
        }
    }
    else if (isVideoScrollableActionBar(self, node)) {
        /*
        Structure for the latest design
        No existing ELMTextNode to work with :(

        ELMContainerNode root
        |-ELMContainerNode
            |-ELMContainerNode
            |-ELMContainerNode
            |-ELMContainerNode id.video.non_scrollable_action_bar
                |-ELMContainerNode
                |-ELMContainerNode
                    |-ELMContainerNode id.video.like.button
                    |-ELMContainerNode
                        |-ELMContainerNode
                        |-ELMContainerNode
                            |-ELMAnimatedVectorNode
                |-ELMContainerNode
                |-ELMContainerNode
                    |-ELMContainerNode id.video.dislike.button
                    |-ELMImageNode
                |-ELMContainerNode
                |-ELMContainerNode
                |-ELMContainerNode
                |-ELMContainerNode
        */
        int pairMode = -1;
        BOOL isDislikeButtonModified = NO;
        ASDisplayNode *containerNode = node;
        ELMContainerNode *likeNode;

        if (![containerNode isKindOfClass:%c(ELMCellNode)]) {
            HBLogDebug(@"RYD: Container node is not ELMCellNode, instead found %@", containerNode);
            return node;
        }

        do {
            containerNode = [containerNode.yogaChildren firstObject];
            if (containerNode.yogaChildren.count == 2)
                containerNode = containerNode.yogaChildren[1];
        } while (containerNode.yogaChildren.count == 1);

        likeNode = [containerNode.yogaChildren firstObject];
        if (![likeNode.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) {
            HBLogDebug(@"RYD: Like button not found, instead found %@", likeNode.accessibilityIdentifier);
            return node;
        }

        NSString *videoId = getVideoId(node);
        if (videoId == nil) return node;
        if (likeNode.yogaChildren.count == 2) {
            ELMContainerNode *dislikeNode = [containerNode.yogaChildren lastObject];
            isDislikeButtonModified = dislikeNode.yogaChildren.count == 2;
            id targetNode = likeNode.yogaChildren[1];
            if ([targetNode isKindOfClass:%c(YTRollingNumberNode)]) {
                likeRollingNumberNode = (YTRollingNumberNode *)targetNode;
                if (isDislikeButtonModified)
                    dislikeRollingNumberNode = dislikeNode.yogaChildren[1];
                else {
                    id elementContext = [likeRollingNumberNode valueForKey:@"_context"];
                    overrideNodeCreation = 1;
                    dislikeRollingNumberNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:likeRollingNumberNode.element materializationContext:&elementContext];
                    overrideNodeCreation = 0;
                    dislikeRollingNumberNode.updatedCount = FETCHING;
                    dislikeRollingNumberNode.updatedCountNumber = @(0);
                    [dislikeRollingNumberNode updateRollingNumberView];
                    [dislikeNode addYogaChild:dislikeRollingNumberNode];
                    [dislikeNode.view addSubview:dislikeRollingNumberNode.view];
                    pairMode = 0;
                }
            } else if ([targetNode isKindOfClass:%c(ELMTextNode)]) {
                likeTextNode = (ELMTextNode *)targetNode;
                if (isDislikeButtonModified)
                    dislikeTextNode = dislikeNode.yogaChildren[1];
                else {
                    id elementContext = [likeTextNode valueForKey:@"_context"];
                    overrideNodeCreation = 2;
                    dislikeTextNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:likeTextNode.element materializationContext:&elementContext];
                    overrideNodeCreation = 0;
                    mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                    dislikeTextNode.attributedText = mutableDislikeText;
                    [dislikeNode addYogaChild:dislikeTextNode];
                    [dislikeNode.view addSubview:dislikeTextNode.view];
                    pairMode = 0;
                }
            }
        } else {
            dislikeTextNode = likeNode.yogaChildren[1];
            if (![dislikeTextNode isKindOfClass:%c(ELMTextNode)]) {
                HBLogDebug(@"RYD: Dislike button not found, instead found %@", dislikeTextNode);
                return node;
            }
            mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:dislikeTextNode.attributedText];
            mutableDislikeText.mutableString.string = FETCHING;
            dislikeTextNode.attributedText = mutableDislikeText;
        }
        self.hasDislikeIntent = YES;
        BOOL shouldFetchVote = (ExactLikeNumber() || UseRYDLikeData()) || !isDislikeButtonModified;
        if (shouldFetchVote) {
            getVoteAndModifyButtons(
                videoId,
                pairMode,
                ^(NSString *likeCount, NSNumber *likeNumber) {
                    if (likeRollingNumberNode) {
                        likeRollingNumberNode.updatedCount = likeCount;
                        likeRollingNumberNode.updatedCountNumber = likeNumber;
                        [likeRollingNumberNode updateRollingNumberView];
                        [likeRollingNumberNode relayoutNode];
                    } else {
                        NSMutableAttributedString *mutableLikeText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                        mutableLikeText.mutableString.string = likeCount;
                        setTextColor(mutableLikeText);
                        likeTextNode.attributedText = mutableLikeText;
                        likeTextNode.accessibilityLabel = likeCount;
                    }
                },
                ^(NSString *dislikeCount, NSNumber *dislikeNumber) {
                    if (isDislikeButtonModified) return;
                    NSString *dislikeString;
                    switch (pairMode) {
                        case -1:
                            dislikeString = dislikeCount;
                            break;
                        case 0:
                            dislikeString = [NSString stringWithFormat:@"  %@ ", dislikeCount];
                            break;
                    }
                    if (dislikeRollingNumberNode) {
                        dislikeRollingNumberNode.updatedCount = dislikeString;
                        dislikeRollingNumberNode.updatedCountNumber = dislikeNumber;
                        [dislikeRollingNumberNode updateRollingNumberView];
                        [dislikeRollingNumberNode relayoutNode];
                    } else {
                        mutableDislikeText.mutableString.string = dislikeString;
                        setTextColor(mutableDislikeText);
                        dislikeTextNode.attributedText = mutableDislikeText;
                        dislikeTextNode.accessibilityLabel = dislikeCount;
                    }
                }
            );
        }
    }
    return node;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    if (!self.hasDislikeIntent || TweakEnabled()) return;
    if (dislikeRollingNumberNode) {
        YTRollingNumberView *likeView = [likeRollingNumberNode valueForKey:@"_rollingNumberView"];
        [dislikeRollingNumberNode updateCount:dislikeRollingNumberNode.updatedCount color:likeView.color];
    }
    if (infoDislikeRollingNumberNode) {
        YTRollingNumberView *likeView = [infoLikeRollingNumberNode valueForKey:@"_rollingNumberView"];
        [infoDislikeRollingNumberNode updateCount:infoDislikeRollingNumberNode.updatedCount color:likeView.color];
    }
    if (dislikeTextNode) {
        NSString *dislikeText = dislikeTextNode.attributedText.string;
        mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
        mutableDislikeText.mutableString.string = dislikeText;
        dislikeTextNode.attributedText = mutableDislikeText;
    }
    if (infoLikeTextNode) {
        NSString *likeDislikeText = infoLikeTextNode.attributedText.string;
        NSMutableAttributedString *mutableInfoLikeDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:infoLikeTextNode.attributedText];
        mutableInfoLikeDislikeText.mutableString.string = likeDislikeText;
        infoLikeTextNode.attributedText = mutableInfoLikeDislikeText;
    }
}

%end

static void setTextNodeColor(ELMTextNode *node, UIColor *color) {
    if (node == nil) return;
    NSString *text = node.attributedText.string;
    NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{ NSForegroundColorAttributeName: color }];
    node.attributedText = attributedText;
}

%hook YTAsyncCollectionView

- (void)pageStyleDidChange:(NSInteger)pageStyle {
    %orig;
    if (![self.pageStylingDelegate isKindOfClass:%c(YTWatchNextResultsViewController)]) return;
    YTCommonColorPalette *colorPalette = currentColorPalette();
    UIColor *textColor = [colorPalette textPrimary];
    setTextNodeColor(likeTextNode, textColor);
    setTextNodeColor(dislikeTextNode, textColor);
}

%end

static void layoutActionBar(YTReelWatchPlaybackOverlayView *self) {
    if (!TweakEnabled() || self.didGetVote) return;
    id spvc = [self parentResponder];
    YTReelModel *model = [spvc valueForKey:@"_model"];
    NSString *videoId;
    @try {
        videoId = [model endpoint].reelWatchEndpoint.videoId;
    } @catch (id ex) {
        videoId = [model command].reelWatchEndpoint.videoId;
        if (videoId.length == 0 && [spvc isKindOfClass:%c(YTShortsPlayerViewController)])
            videoId = [[[(YTShortsPlayerViewController *)spvc currentVideo] singleVideo] videoId];
    }
    HBLogDebug(@"RYD: Short ID: %@", videoId);
    if (videoId == nil) return;
    YTELMView *elmView = nil;
    @try {
        elmView = [self valueForKey:@"_actionBarView"];
    } @catch (id ex) {}
    if (elmView == nil) {
        @try {
            YTReelElementAsyncComponentView *view = [self valueForKey:@"_actionBarComponentView"];
            elmView = [view valueForKey:@"_elementView"];
        } @catch (id ex) {}
    }
    BOOL isNested = NO;
    if (elmView == nil) {
        @try {
            YTReelElementAsyncComponentView *playerOverlayView = [self valueForKey:@"_playerOverlayView"];
            elmView = [playerOverlayView valueForKey:@"_elementView"];
            isNested = YES;
        } @catch (id ex) {}
    }
    if (elmView == nil) return;
    if ([elmView isKindOfClass:%c(YTReelWatchActionBarView)])
        elmView = [elmView valueForKey:@"_actionBarElement"];
    ELMContainerNode *containerNode;
    if (isNested) {
        ELMContainerNode *node = [elmView valueForKey:@"_rootNode"];
        node = [node.yogaChildren firstObject];
        containerNode = [node.yogaChildren yt_objectAtIndexOrNil:1];
    } else
        containerNode = [elmView valueForKey:@"_rootNode"];
    ELMContainerNode *likeNode = [containerNode.yogaChildren firstObject];
    ELMContainerNode *dislikeNode = [containerNode.yogaChildren yt_objectAtIndexOrNil:1];
    BOOL foundLikeButton = NO;
    BOOL foundDislikeButton = NO;
    @try {
        ELMComponent *likeOwningComponent = [[likeNode controller] owningComponent];
        if ([likeOwningComponent owningComponent]) likeOwningComponent = [likeOwningComponent owningComponent];
        foundLikeButton = [[likeOwningComponent templateURI] hasPrefix:@"reel_like_button"];
        ELMComponent *dislikeOwningComponent = [[dislikeNode controller] owningComponent];
        if ([dislikeOwningComponent owningComponent]) dislikeOwningComponent = [dislikeOwningComponent owningComponent];
        foundDislikeButton = [[dislikeOwningComponent templateURI] hasPrefix:@"reel_dislike_button"];
    } @catch (id ex) {
        HBLogDebug(@"RYD: Error checking if like/dislike button is found: %@", ex);
    }
    if (!foundLikeButton) {
        do {
            likeNode = [likeNode.yogaChildren firstObject];
        } while ([likeNode.accessibilityIdentifier isEqualToString:@"id.reel_like_button"]);
        do {
            likeNode = [likeNode.yogaChildren firstObject];
        } while (likeNode.yogaChildren.count == 1);
    }
    if (!foundDislikeButton) {
        do {
            dislikeNode = [dislikeNode.yogaChildren firstObject];
        } while ([dislikeNode.accessibilityIdentifier isEqualToString:@"id.reel_dislike_button"]);
        do {
            dislikeNode = [dislikeNode.yogaChildren firstObject];
        } while (dislikeNode.yogaChildren.count == 1);
    }
    NSArray *likeChildren = likeNode.yogaChildren;
    if (likeChildren.count == 1) likeChildren = ((ASDisplayNode *)[likeNode.yogaChildren firstObject]).yogaChildren;
    ELMTextNode *shortLikeTextNode = [likeChildren yt_objectAtIndexOrNil:1];
    NSArray *dislikeChildren = dislikeNode.yogaChildren;
    if (dislikeChildren.count == 1) dislikeChildren = ((ASDisplayNode *)[dislikeNode.yogaChildren firstObject]).yogaChildren;
    ELMTextNode *shortDislikeTextNode = [dislikeChildren yt_objectAtIndexOrNil:1];
    if (shortLikeTextNode == nil || shortDislikeTextNode == nil || ![shortLikeTextNode isKindOfClass:%c(ELMTextNode)] || ![shortDislikeTextNode isKindOfClass:%c(ELMTextNode)]) {
        HBLogDebug(@"RYD: Short like or dislike text node not found");
        return;
    }
    __block NSMutableAttributedString *shortMutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:shortLikeTextNode.attributedText];
    shortMutableDislikeText.mutableString.string = FETCHING;
    shortDislikeTextNode.attributedText = shortMutableDislikeText;
    getVoteAndModifyButtons(
        videoId,
        -1,
        ^(NSString *likeCount, NSNumber *likeNumber) {
            NSMutableAttributedString *shortMutableLikeText = [[NSMutableAttributedString alloc] initWithAttributedString:shortLikeTextNode.attributedText];
            shortMutableLikeText.mutableString.string = likeCount;
            shortLikeTextNode.attributedText = shortMutableLikeText;
            shortLikeTextNode.accessibilityLabel = likeCount;
        },
        ^(NSString *dislikeCount, NSNumber *dislikeNumber) {
            shortMutableDislikeText.mutableString.string = dislikeCount;
            shortDislikeTextNode.attributedText = shortMutableDislikeText;
            shortDislikeTextNode.accessibilityLabel = dislikeCount;
        }
    );
    self.didGetVote = YES;
}

%hook YTReelWatchPlaybackOverlayView

%property (assign, nonatomic) BOOL didGetVote;

- (void)layoutActionBar {
    %orig;
    layoutActionBar(self);
}

%end

%hook YTReelWatchPlaybackOverlayViewSub

%property (assign, nonatomic) BOOL didGetVote;

- (void)layoutActionBar {
    %orig;
    layoutActionBar((YTReelWatchPlaybackOverlayView *)self);
}

%end

%hook ELMCellNode

%property (nonatomic, strong) RYDMetadataState *rydMetadata;

- (void)didEnterHierarchy {
    %orig;
    configureVisibleMetadataCell(self);
}

- (void)layoutDidFinish {
    %orig;
    configureVisibleMetadataCell(self);
}

%end

%hook ELMTextNode

%property (nonatomic, strong) RYDMetadataState *rydMetadata;

- (void)updateAttributedText {
    %orig;
    updateMetadataTextNode(self);
    updateMetadataTail(self);
}

// Later responses for the same watch page reuse the node tree and reset the
// text through setElement: without going through updateAttributedText.
- (void)setElement:(ELMElement *)element {
    %orig;
    updateMetadataTextNode(self);
    updateMetadataTail(self);
}

%end

%hook YTRollingNumberNode

%property (strong, nonatomic) NSString *updatedCount;
%property (strong, nonatomic) NSNumber *updatedCountNumber;
%property (strong, nonatomic) RYDMetadataState *rydMetadata;

- (id)initWithElement:(id)element context:(id)context {
    self = %orig;
    if (self) {
        self.updatedCount = nil;
        self.updatedCountNumber = nil;
    }
    return self;
}

- (void)updateRollingNumberView {
    %orig;
    if (self.updatedCount && self.updatedCountNumber)
        [self updateCount:self.updatedCount color:nil];
    updateMetadataRollingNumber(self);
}

%new(v@:@@)
- (void)updateCount:(NSString *)updatedCount_ color:(UIColor *)color_ {
    YTRollingNumberView *view = [self valueForKey:@"_rollingNumberView"];
    NSString *updatedCount = [NSString stringWithFormat:@" %@", updatedCount_];
    // See updateMetadataRollingNumber: the native update that just ran may still
    // be rolling reused digit views toward the like count.
    setRollingNumberText(view, @"", self.updatedCountNumber, color_);
    setRollingNumberText(view, updatedCount, self.updatedCountNumber, color_);
}

%end

%hook ELMNodeFactory

- (Class)classForElement:(id)element materializationContext:(const void *)context {
    switch (overrideNodeCreation) {
        case 1:
            return %c(YTRollingNumberNode);
        case 2:
            return %c(ELMTextNode);
        default:
            return %orig;
    }
}

%end

%ctor {
    cache = [NSCache new];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:DidShowEnableVoteSubmissionAlertKey] && !VoteSubmissionEnabled()) {
        [defaults setBool:YES forKey:DidShowEnableVoteSubmissionAlertKey];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSBundle *tweakBundle = RYDBundle();
            YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                enableVoteSubmission(YES);
            } actionTitle:_LOC([NSBundle mainBundle], @"settings.yes")];
            alertView.title = @(TWEAK_NAME);
            alertView.subtitle = [NSString stringWithFormat:LOC(@"WANT_TO_ENABLE"), @(API_URL), alertView.title, LOC(@"ENABLE_VOTE_SUBMIT")];
            [alertView show];
        });
    }
    [[NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/Frameworks/Module_Framework.framework", NSBundle.mainBundle.bundlePath]] load];
    localizedDislikeText = [RYDBundle() localizedStringForKey:@"DISLIKES"
        value:_LOC([NSBundle mainBundle], @"offline.dislike") table:nil];
    %init;
}
