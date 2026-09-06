#import "KCDetector.h"
#import "KCLog.h"
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>
#import <os/lock.h>

static NSString *const kKCModelName = @"YOLOv3TinyInt8LUT";
static NSString *const kKCInputConfidence = @"confidenceThreshold";
static NSString *const kKCInputIoU = @"iouThreshold";

#pragma mark - Nhà cung cấp ngưỡng cho model

/// Model YOLOv3-Tiny của Apple có hai đầu vào tuỳ chọn "confidenceThreshold" và "iouThreshold".
/// Chỉ dùng khi model thật sự khai báo chúng (kiểm tra lúc nạp, không giả định).
@interface KCThresholdProvider : NSObject <MLFeatureProvider>
@property (nonatomic, strong) NSSet<NSString *> *names;
@property (nonatomic, assign) double confidence;
@property (nonatomic, assign) double iou;
@end

@implementation KCThresholdProvider

- (NSSet<NSString *> *)featureNames {
    return self.names ?: [NSSet set];
}

- (MLFeatureValue *)featureValueForName:(NSString *)featureName {
    if ([featureName isEqualToString:kKCInputConfidence]) return [MLFeatureValue featureValueWithDouble:self.confidence];
    if ([featureName isEqualToString:kKCInputIoU]) return [MLFeatureValue featureValueWithDouble:self.iou];
    return nil;
}

@end

#pragma mark - KCDetector

@interface KCDetector ()
@property (nonatomic, strong) VNCoreMLModel *visionModel;
@property (nonatomic, strong) VNCoreMLRequest *farRequest;
@property (nonatomic, strong) VNCoreMLRequest *nearRequest;
@property (nonatomic, strong) dispatch_queue_t inferenceQueue;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) double inferenceFPS;
@property (nonatomic, assign) NSTimeInterval lastInferenceSeconds;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, strong) NSSet<NSString *> *vehicleLabels;
@property (nonatomic, assign) NSUInteger inferenceCounter;
@property (nonatomic, assign) NSUInteger fpsCount;
@property (nonatomic, assign) CFAbsoluteTime fpsWindowStart;
@property (nonatomic, assign) CFAbsoluteTime lastSubmitTime;
@property (nonatomic, assign) BOOL loggedFirstResults;
@property (nonatomic, assign) BOOL loggedRawFarBox;
@end

@implementation KCDetector {
    os_unfair_lock _busyLock;
    BOOL _busy;
}

- (instancetype)init {
    if ((self = [super init])) {
        _busyLock = OS_UNFAIR_LOCK_INIT;
        _inferenceQueue = dispatch_queue_create("com.khoangcachantoan.inference", DISPATCH_QUEUE_SERIAL);
        _maxInferenceFPS = 15.0;
        _confidenceThreshold = 0.30f;
        _iouThreshold = 0.45f;
        // Hệ Vision: gốc toạ độ ở góc DƯỚI-trái. x 25–75 %, y 30–80 % của khung.
        _farRegionOfInterest = CGRectMake(0.25, 0.30, 0.50, 0.50);
        _statusText = @"model chưa nạp";
        _vehicleLabels = [NSSet setWithArray:@[@"car", @"truck", @"bus"]];
    }
    return self;
}

#pragma mark - Nạp model

- (BOOL)loadModelWithError:(NSError **)error {
    NSURL *url = [[NSBundle mainBundle] URLForResource:kKCModelName withExtension:@"mlmodelc"];
    if (!url) {
        KCLogf(@"detector: KHONG tim thay %@.mlmodelc trong bundle %@", kKCModelName, [NSBundle mainBundle].bundlePath);
        self.statusText = @"thiếu model";
        if (error) *error = [NSError errorWithDomain:@"KCDetector" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy model trong bundle"}];
        return NO;
    }

    MLModelConfiguration *cfg = [[MLModelConfiguration alloc] init];
    cfg.computeUnits = MLComputeUnitsAll;   // A11 không có Neural Engine dùng được -> chạy GPU

    NSError *loadErr = nil;
    MLModel *model = [MLModel modelWithContentsOfURL:url configuration:cfg error:&loadErr];
    if (!model) {
        KCLogf(@"detector: nap model that bai: %@", loadErr);
        self.statusText = @"model lỗi";
        if (error) *error = loadErr;
        return NO;
    }

    [self logModelDescription:model.modelDescription];

    NSError *vnErr = nil;
    VNCoreMLModel *vnModel = [VNCoreMLModel modelForMLModel:model error:&vnErr];
    if (!vnModel) {
        KCLogf(@"detector: VNCoreMLModel that bai: %@", vnErr);
        self.statusText = @"Vision lỗi";
        if (error) *error = vnErr;
        return NO;
    }

    // Chỉ nối ngưỡng khi model KHAI BÁO đúng hai đầu vào đó; nếu không, lọc ở tầng app.
    NSDictionary<NSString *, MLFeatureDescription *> *inputs = model.modelDescription.inputDescriptionsByName;
    NSMutableSet<NSString *> *available = [NSMutableSet set];
    if (inputs[kKCInputConfidence]) [available addObject:kKCInputConfidence];
    if (inputs[kKCInputIoU]) [available addObject:kKCInputIoU];
    if (available.count > 0) {
        KCThresholdProvider *provider = [[KCThresholdProvider alloc] init];
        provider.names = available;
        provider.confidence = self.confidenceThreshold;
        provider.iou = self.iouThreshold;
        vnModel.featureProvider = provider;
        KCLogf(@"detector: dat nguong qua featureProvider %@ (conf=%.2f iou=%.2f)",
               [available.allObjects componentsJoinedByString:@","], self.confidenceThreshold, self.iouThreshold);
    } else {
        KCLogf(@"detector: model khong co dau vao nguong -> loc o tang app (conf>=%.2f)", self.confidenceThreshold);
    }

    self.visionModel = vnModel;
    self.farRequest = [self makeRequestWithRegionOfInterest:self.farRegionOfInterest];
    self.nearRequest = [self makeRequestWithRegionOfInterest:CGRectMake(0, 0, 1, 1)];
    self.ready = YES;
    self.statusText = @"sẵn sàng";
    KCLogf(@"detector: san sang (ROI xa = %.2f,%.2f,%.2f,%.2f)",
           self.farRegionOfInterest.origin.x, self.farRegionOfInterest.origin.y,
           self.farRegionOfInterest.size.width, self.farRegionOfInterest.size.height);
    return YES;
}

- (VNCoreMLRequest *)makeRequestWithRegionOfInterest:(CGRect)roi {
    VNCoreMLRequest *r = [[VNCoreMLRequest alloc] initWithModel:self.visionModel];
    r.imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;
    r.regionOfInterest = roi;
    return r;
}

- (void)logModelDescription:(MLModelDescription *)desc {
    NSMutableArray<NSString *> *ins = [NSMutableArray array];
    [desc.inputDescriptionsByName enumerateKeysAndObjectsUsingBlock:^(NSString *k, MLFeatureDescription *v, BOOL *stop) {
        [ins addObject:[NSString stringWithFormat:@"%@(type=%ld%@)", k, (long)v.type,
                        v.imageConstraint ? [NSString stringWithFormat:@" %lux%lu",
                                             (unsigned long)v.imageConstraint.pixelsWide,
                                             (unsigned long)v.imageConstraint.pixelsHigh] : @""]];
    }];
    NSMutableArray<NSString *> *outs = [NSMutableArray array];
    [desc.outputDescriptionsByName enumerateKeysAndObjectsUsingBlock:^(NSString *k, MLFeatureDescription *v, BOOL *stop) {
        [outs addObject:[NSString stringWithFormat:@"%@(type=%ld)", k, (long)v.type]];
    }];
    KCLogf(@"detector: model inputs = [%@]", [ins componentsJoinedByString:@", "]);
    KCLogf(@"detector: model outputs = [%@]", [outs componentsJoinedByString:@", "]);

    NSArray *labels = desc.classLabels;
    if (labels.count > 0) {
        KCLogf(@"detector: %lu nhan: %@", (unsigned long)labels.count, [labels componentsJoinedByString:@","]);
        // Nhãn xe máy có thể là "motorbike" hoặc "motorcycle" tuỳ bản model -> khớp theo tiền tố "motor".
        NSMutableSet<NSString *> *keep = [NSMutableSet setWithObjects:@"car", @"truck", @"bus", nil];
        for (id l in labels) {
            NSString *s = [l description].lowercaseString;
            if ([s hasPrefix:@"motor"]) [keep addObject:s];
        }
        self.vehicleLabels = keep;
        KCLogf(@"detector: giu lai cac lop: %@", [[keep allObjects] componentsJoinedByString:@","]);
    } else {
        KCLogf(@"detector: modelDescription khong co classLabels (model pipeline) -> loc theo ten nhan luc chay");
    }
}

#pragma mark - Nhận khung hình

- (void)submitPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation {
    if (!self.ready || pixelBuffer == NULL) return;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double minInterval = (self.maxInferenceFPS > 0) ? (1.0 / self.maxInferenceFPS) : 0;
    if (self.lastSubmitTime > 0 && (now - self.lastSubmitTime) < minInterval) return;

    BOOL run = NO;
    os_unfair_lock_lock(&_busyLock);
    if (!_busy) { _busy = YES; run = YES; }
    os_unfair_lock_unlock(&_busyLock);
    if (!run) return;                      // đang bận -> bỏ khung (mục 5.1)

    self.lastSubmitTime = now;
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(self.inferenceQueue, ^{
        @try {
            [self runOnPixelBuffer:pixelBuffer orientation:orientation];
        } @catch (NSException *e) {
            KCLogf(@"detector: exception khi suy luan: %@", e);
        } @finally {
            CVPixelBufferRelease(pixelBuffer);
            os_unfair_lock_lock(&self->_busyLock);
            self->_busy = NO;
            os_unfair_lock_unlock(&self->_busyLock);
        }
    });
}

- (void)runOnPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation {
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    self.inferenceCounter += 1;
    BOOL runNear = (self.inferenceCounter % 3 == 0);   // kênh gần: 1 trên 3 lần suy luận

    NSMutableArray<VNRequest *> *requests = [NSMutableArray arrayWithObject:self.farRequest];
    if (runNear) [requests addObject:self.nearRequest];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer
                                                                             orientation:orientation
                                                                                 options:@{}];
    NSError *err = nil;
    if (![handler performRequests:requests error:&err]) {
        KCLogf(@"detector: performRequests loi: %@", err);
        return;
    }

    NSMutableArray<KCDetection *> *all = [NSMutableArray array];
    [all addObjectsFromArray:[self detectionsFromRequest:self.farRequest far:YES]];
    if (runNear) [all addObjectsFromArray:[self detectionsFromRequest:self.nearRequest far:NO]];

    NSArray<KCDetection *> *merged = [self nonMaxSuppress:all iouLimit:0.5];

    CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
    self.lastInferenceSeconds = t1 - t0;
    [self tickFPS:t1];

    if (!self.loggedFirstResults) {
        self.loggedFirstResults = YES;
        KCLogf(@"detector: lan suy luan dau: %lu vat the (%.0f ms)", (unsigned long)merged.count, self.lastInferenceSeconds * 1000);
        for (KCDetection *d in merged) KCLogf(@"detector:   %@", d);
    }

    id<KCDetectorDelegate> d = self.delegate;
    if (d) [d detector:self didFindVehicles:merged inferenceTime:self.lastInferenceSeconds];
}

- (void)tickFPS:(CFAbsoluteTime)now {
    if (self.fpsWindowStart == 0) self.fpsWindowStart = now;
    self.fpsCount += 1;
    CFAbsoluteTime dt = now - self.fpsWindowStart;
    if (dt >= 1.0) {
        self.inferenceFPS = self.fpsCount / dt;
        self.fpsCount = 0;
        self.fpsWindowStart = now;
    }
}

#pragma mark - Quy đổi kết quả

- (NSArray<KCDetection *> *)detectionsFromRequest:(VNCoreMLRequest *)request far:(BOOL)far {
    NSMutableArray<KCDetection *> *out = [NSMutableArray array];
    CGRect roi = request.regionOfInterest;
    for (id result in request.results) {
        if (![result isKindOfClass:[VNRecognizedObjectObservation class]]) continue;
        VNRecognizedObjectObservation *obs = (VNRecognizedObjectObservation *)result;
        VNClassificationObservation *top = obs.labels.firstObject;
        if (!top) continue;
        NSString *label = top.identifier.lowercaseString;
        if (![self isVehicleLabel:label]) continue;
        float conf = MAX(top.confidence, 0.0f);
        if (conf < self.confidenceThreshold) continue;

        // Vision trả bbox chuẩn hoá TƯƠNG ĐỐI ROI, gốc DƯỚI-trái.
        // Đưa về toàn khung rồi lật trục y sang gốc TRÊN-trái (quy ước dùng trong app).
        // Phép "gỡ cắt" tuyến tính này chỉ đúng vì imageCropAndScaleOption = ScaleFill
        // (ROI được co thẳng vào ô vuông đầu vào của model, không viền đen, không cắt giữa).
        CGRect bb = obs.boundingBox;
        CGFloat x = roi.origin.x + bb.origin.x * roi.size.width;
        CGFloat w = bb.size.width * roi.size.width;
        CGFloat h = bb.size.height * roi.size.height;
        CGFloat yBottomLeft = roi.origin.y + bb.origin.y * roi.size.height;
        CGFloat yTopLeft = 1.0 - (yBottomLeft + h);

        if (w <= 0 || h <= 0) continue;

        // Model có thể đoán khung tràn ra ngoài mép -> cắt về trong khung hình.
        CGRect n = CGRectIntersection(CGRectMake(x, yTopLeft, w, h), CGRectMake(0, 0, 1, 1));
        if (CGRectIsNull(n) || n.size.width <= 0 || n.size.height <= 0) continue;

        if (far && !self.loggedRawFarBox) {
            self.loggedRawFarBox = YES;
            // Bằng chứng để kiểm tra hệ toạ độ: nếu bbox thô nằm ngoài phạm vi ROI
            // thì nó KHÔNG phải toạ độ toàn khung, tức đúng là tương đối ROI.
            KCLogf(@"detector: bbox tho kenh xa = (%.3f,%.3f,%.3f,%.3f) -> toan khung (%.3f,%.3f,%.3f,%.3f)",
                   bb.origin.x, bb.origin.y, bb.size.width, bb.size.height,
                   n.origin.x, n.origin.y, n.size.width, n.size.height);
        }

        KCDetection *det = [[KCDetection alloc] init];
        det.nrect = n;
        det.label = label;
        det.confidence = conf;
        det.fromFarChannel = far;
        [out addObject:det];
    }
    return out;
}

- (BOOL)isVehicleLabel:(NSString *)label {
    if (!label.length) return NO;
    if ([self.vehicleLabels containsObject:label]) return YES;
    return [label hasPrefix:@"motor"];   // motorbike / motorcycle
}

/// Gộp hai kênh: giữ vật thể tin cậy cao, bỏ vật thể trùng IoU vượt ngưỡng.
- (NSArray<KCDetection *> *)nonMaxSuppress:(NSArray<KCDetection *> *)input iouLimit:(CGFloat)limit {
    if (input.count < 2) return input;
    NSArray<KCDetection *> *sorted = [input sortedArrayUsingComparator:^NSComparisonResult(KCDetection *a, KCDetection *b) {
        if (a.confidence > b.confidence) return NSOrderedAscending;
        if (a.confidence < b.confidence) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray<KCDetection *> *kept = [NSMutableArray array];
    for (KCDetection *cand in sorted) {
        BOOL overlaps = NO;
        for (KCDetection *k in kept) {
            if (KCRectIoU(cand.nrect, k.nrect) > limit) { overlaps = YES; break; }
        }
        if (!overlaps) [kept addObject:cand];
    }
    return kept;
}

@end
