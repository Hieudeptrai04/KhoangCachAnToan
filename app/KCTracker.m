#import "KCTracker.h"
#import "KCLog.h"

@implementation KCTrackerResult
@end

/// Một vệt bám giữa các khung hình.
@interface KCTrack : NSObject
@property (nonatomic, assign) NSInteger trackID;
@property (nonatomic, assign) CGRect nrect;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSTimeInterval lastSeen;
@property (nonatomic, assign) NSInteger hits;
@end

@implementation KCTrack
@end

@interface KCTracker ()
@property (nonatomic, strong) NSMutableArray<KCTrack *> *tracks;
@property (nonatomic, assign) NSInteger nextTrackID;
@property (nonatomic, assign) NSInteger leaderTrackID;
@property (nonatomic, assign) NSInteger candidateTrackID;
@property (nonatomic, assign) NSInteger candidateStreak;
@property (nonatomic, strong) KCDetection *lastLeader;
@property (nonatomic, assign) NSTimeInterval lastLeaderSeen;
- (KCTrackerResult *)unsafeUpdateWithDetections:(NSArray<KCDetection *> *)detections timestamp:(NSTimeInterval)timestamp;
@end

@implementation KCTracker

- (instancetype)init {
    if ((self = [super init])) {
        _tracks = [NSMutableArray array];
        _nextTrackID = 1;
        _leaderTrackID = -1;
        _candidateTrackID = -1;
        _horizonY = 0.5;
        _laneHalfWidthBottom = 0.25;
        _laneHalfWidthTop = 0.05;
        _matchIoU = 0.3;
        _leaderSwitchFrames = 5;
        _leaderHoldSeconds = 1.0;
    }
    return self;
}

- (void)reset {
    // Có thể gọi từ main queue trong khi hàng đợi suy luận đang cập nhật -> khoá.
    @synchronized (self) {
        [self.tracks removeAllObjects];
        self.leaderTrackID = -1;
        self.candidateTrackID = -1;
        self.candidateStreak = 0;
        self.lastLeader = nil;
        self.lastLeaderSeen = 0;
    }
}

- (CGFloat)laneHalfWidthAtY:(CGFloat)y {
    CGFloat h = self.horizonY;
    if (y <= h) return self.laneHalfWidthTop;
    CGFloat denom = 1.0 - h;
    CGFloat t = (denom > 0.0001) ? ((y - h) / denom) : 1.0;
    t = MIN(MAX(t, 0.0), 1.0);
    return self.laneHalfWidthTop + (self.laneHalfWidthBottom - self.laneHalfWidthTop) * t;
}

- (BOOL)isInLane:(KCDetection *)d {
    CGFloat by = CGRectGetMaxY(d.nrect);      // cạnh đáy
    CGFloat bx = CGRectGetMidX(d.nrect);      // giữa cạnh đáy
    return fabs(bx - 0.5) <= [self laneHalfWidthAtY:by];
}

#pragma mark - Cập nhật

- (KCTrackerResult *)updateWithDetections:(NSArray<KCDetection *> *)detections timestamp:(NSTimeInterval)timestamp {
    @synchronized (self) {
        return [self unsafeUpdateWithDetections:detections timestamp:timestamp];
    }
}

- (KCTrackerResult *)unsafeUpdateWithDetections:(NSArray<KCDetection *> *)detections timestamp:(NSTimeInterval)timestamp {
    NSArray<KCDetection *> *dets = [[NSArray alloc] initWithArray:detections copyItems:YES];

    [self assignTrackIDsTo:dets timestamp:timestamp];

    // Đánh dấu xe cùng làn và tìm ứng viên dẫn đầu (cạnh đáy thấp nhất = gần nhất).
    KCDetection *best = nil;
    for (KCDetection *d in dets) {
        d.inLane = [self isInLane:d];
        if (!d.inLane) continue;
        if (!best || CGRectGetMaxY(d.nrect) > CGRectGetMaxY(best.nrect)) best = d;
    }

    KCDetection *currentLeaderDet = nil;
    if (self.leaderTrackID >= 0) {
        for (KCDetection *d in dets) {
            if (d.trackID == self.leaderTrackID) { currentLeaderDet = d; break; }
        }
    }

    // Đổi mục tiêu chỉ khi ứng viên mới thắng liên tiếp đủ số khung (chống nhấp nháy).
    if (best) {
        if (currentLeaderDet && best.trackID == currentLeaderDet.trackID) {
            self.candidateTrackID = -1;
            self.candidateStreak = 0;
        } else if (!currentLeaderDet) {
            [self setLeaderTo:best.trackID reason:@"khong con xe dan dau cu"];
            currentLeaderDet = best;
        } else {
            if (best.trackID == self.candidateTrackID) self.candidateStreak += 1;
            else { self.candidateTrackID = best.trackID; self.candidateStreak = 1; }
            if (self.candidateStreak >= self.leaderSwitchFrames) {
                [self setLeaderTo:best.trackID reason:[NSString stringWithFormat:@"thang %ld khung lien tiep", (long)self.candidateStreak]];
                currentLeaderDet = best;
            }
        }
    } else {
        self.candidateTrackID = -1;
        self.candidateStreak = 0;
    }

    KCTrackerResult *result = [[KCTrackerResult alloc] init];
    result.detections = dets;

    if (currentLeaderDet) {
        currentLeaderDet.isLeader = YES;
        self.lastLeader = [currentLeaderDet copy];
        self.lastLeaderSeen = timestamp;
        result.leader = currentLeaderDet;
        result.leaderLost = NO;
        result.leaderTrackID = currentLeaderDet.trackID;
    } else if (self.lastLeader && (timestamp - self.lastLeaderSeen) <= self.leaderHoldSeconds) {
        result.leader = self.lastLeader;      // giữ giá trị cũ tối đa 1 s
        result.leaderLost = YES;
        result.leaderTrackID = self.lastLeader.trackID;
    } else {
        if (self.lastLeader) KCLogf(@"tracker: mat dau xe dan dau qua %.1f s -> bo", self.leaderHoldSeconds);
        self.lastLeader = nil;
        self.leaderTrackID = -1;
        result.leader = nil;
        result.leaderLost = NO;
        result.leaderTrackID = -1;
    }

    [self pruneTracksOlderThan:timestamp - 2.0];
    return result;
}

- (void)setLeaderTo:(NSInteger)trackID reason:(NSString *)reason {
    if (self.leaderTrackID == trackID) return;
    KCLogf(@"tracker: doi xe dan dau %ld -> %ld (%@)", (long)self.leaderTrackID, (long)trackID, reason);
    self.leaderTrackID = trackID;
    self.candidateTrackID = -1;
    self.candidateStreak = 0;
}

/// Khớp từng phát hiện với vệt bám của khung trước theo IoU (tham lam, IoU giảm dần).
- (void)assignTrackIDsTo:(NSArray<KCDetection *> *)dets timestamp:(NSTimeInterval)timestamp {
    NSMutableSet<NSNumber *> *usedTracks = [NSMutableSet set];
    NSMutableArray *pairs = [NSMutableArray array];

    for (NSUInteger di = 0; di < dets.count; di++) {
        KCDetection *d = dets[di];
        for (KCTrack *t in self.tracks) {
            CGFloat iou = KCRectIoU(d.nrect, t.nrect);
            if (iou >= self.matchIoU) {
                [pairs addObject:@{@"iou": @(iou), @"det": @(di), @"track": @(t.trackID)}];
            }
        }
    }
    [pairs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ia = [a[@"iou"] doubleValue], ib = [b[@"iou"] doubleValue];
        if (ia > ib) return NSOrderedAscending;
        if (ia < ib) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableSet<NSNumber *> *usedDets = [NSMutableSet set];
    for (NSDictionary *p in pairs) {
        NSNumber *di = p[@"det"], *tid = p[@"track"];
        if ([usedDets containsObject:di] || [usedTracks containsObject:tid]) continue;
        [usedDets addObject:di];
        [usedTracks addObject:tid];
        KCDetection *d = dets[di.unsignedIntegerValue];
        d.trackID = tid.integerValue;
        for (KCTrack *t in self.tracks) {
            if (t.trackID == tid.integerValue) {
                t.nrect = d.nrect;
                t.label = d.label;
                t.lastSeen = timestamp;
                t.hits += 1;
                break;
            }
        }
    }

    for (NSUInteger di = 0; di < dets.count; di++) {
        if ([usedDets containsObject:@(di)]) continue;
        KCDetection *d = dets[di];
        KCTrack *t = [[KCTrack alloc] init];
        t.trackID = self.nextTrackID++;
        t.nrect = d.nrect;
        t.label = d.label;
        t.lastSeen = timestamp;
        t.hits = 1;
        [self.tracks addObject:t];
        d.trackID = t.trackID;
    }
}

- (void)pruneTracksOlderThan:(NSTimeInterval)cutoff {
    NSMutableArray<KCTrack *> *keep = [NSMutableArray array];
    for (KCTrack *t in self.tracks) {
        if (t.lastSeen >= cutoff) [keep addObject:t];
    }
    self.tracks = keep;
}

@end
