#import "KCDetection.h"

@implementation KCDetection

- (instancetype)init {
    if ((self = [super init])) {
        _trackID = -1;
        _label = @"";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KCDetection *d = [[KCDetection allocWithZone:zone] init];
    d.nrect = _nrect;
    d.label = _label;
    d.confidence = _confidence;
    d.fromFarChannel = _fromFarChannel;
    d.trackID = _trackID;
    d.inLane = _inLane;
    d.isLeader = _isLeader;
    return d;
}

- (CGFloat)widthPixelsForBufferWidth:(CGFloat)bufferWidth {
    return _nrect.size.width * bufferWidth;
}

- (CGFloat)bottomPixelForBufferHeight:(CGFloat)bufferHeight {
    return CGRectGetMaxY(_nrect) * bufferHeight;
}

- (CGFloat)bottomCenterX {
    return CGRectGetMidX(_nrect);
}

- (CGFloat)aspectRatioForBufferWidth:(CGFloat)bufferWidth height:(CGFloat)bufferHeight {
    CGFloat h = _nrect.size.height * bufferHeight;
    if (h <= 0.0001) return 0;
    return (_nrect.size.width * bufferWidth) / h;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<KCDetection %@ %.2f %@ id=%ld rect=(%.3f,%.3f,%.3f,%.3f)%@>",
            _label, _confidence, _fromFarChannel ? @"xa" : @"gan", (long)_trackID,
            _nrect.origin.x, _nrect.origin.y, _nrect.size.width, _nrect.size.height,
            _isLeader ? @" LEADER" : (_inLane ? @" lane" : @"")];
}

@end

CGFloat KCRectIoU(CGRect a, CGRect b) {
    CGRect inter = CGRectIntersection(a, b);
    if (CGRectIsNull(inter) || CGRectIsEmpty(inter)) return 0;
    CGFloat ia = inter.size.width * inter.size.height;
    CGFloat ua = a.size.width * a.size.height + b.size.width * b.size.height - ia;
    if (ua <= 0) return 0;
    return ia / ua;
}
