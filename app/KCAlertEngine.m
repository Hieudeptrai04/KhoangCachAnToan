#import "KCAlertEngine.h"
#import "KCLog.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <math.h>

static const double kKCBeepFrequency = 880.0;
static const double kKCBeepSeconds = 0.12;
static const float kKCBeepAmplitude = 0.35f;

@interface KCAlertEngine ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioPCMBuffer *beepBuffer;
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@property (nonatomic, strong) AVSpeechSynthesisVoice *voice;
@property (nonatomic, strong) UINotificationFeedbackGenerator *feedback;
@property (nonatomic, assign) CFAbsoluteTime lastFire;
@property (nonatomic, assign) BOOL audioReady;
@end

@implementation KCAlertEngine

- (instancetype)init {
    if ((self = [super init])) {
        _beepEnabled = YES;
        _hapticEnabled = YES;
        _speechEnabled = YES;
        _minimumInterval = 3.0;
        _synth = [[AVSpeechSynthesizer alloc] init];
        _voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"vi-VN"];
        if (!_voice) KCLogf(@"alert: khong co giong vi-VN tren may nay");
        _feedback = [[UINotificationFeedbackGenerator alloc] init];
        // KHÔNG dựng audio engine ở đây: chạm vào AVAudioSession trước khi camera khởi động
        // có thể xen vào lúc AVCaptureSession đang thương lượng pipeline. Dựng khi cần dùng.
    }
    return self;
}

#pragma mark - Âm thanh

- (void)configureSession {
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // Trộn với nhạc / dẫn đường, chỉ giảm nhẹ âm nền, không chiếm phiên.
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback
                              mode:AVAudioSessionModeDefault
                           options:(AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers)
                             error:&err];
    if (!ok) KCLogf(@"alert: setCategory loi %@", err);
}

- (void)prepareAudio {
    [self configureSession];

    self.engine = [[AVAudioEngine alloc] init];
    self.player = [[AVAudioPlayerNode alloc] init];
    [self.engine attachNode:self.player];

    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    [self.engine connect:self.player to:self.engine.mainMixerNode format:format];

    AVAudioFrameCount frames = (AVAudioFrameCount)(format.sampleRate * kKCBeepSeconds);
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
    if (!buffer) {
        KCLogf(@"alert: khong tao duoc buffer bip");
        return;
    }
    buffer.frameLength = frames;
    float *data = buffer.floatChannelData[0];
    double twoPiF = 2.0 * M_PI * kKCBeepFrequency / format.sampleRate;
    // Vào và ra êm 5 ms để không nghe tiếng "tạch" ở hai đầu.
    AVAudioFrameCount ramp = (AVAudioFrameCount)(format.sampleRate * 0.005);
    for (AVAudioFrameCount i = 0; i < frames; i++) {
        double env = 1.0;
        if (i < ramp) env = (double)i / ramp;
        else if (i > frames - ramp) env = (double)(frames - i) / ramp;
        data[i] = (float)(sin(twoPiF * i) * kKCBeepAmplitude * env);
    }
    self.beepBuffer = buffer;
    self.audioReady = YES;
    KCLogf(@"alert: da tao bip %.0f Hz, %.0f ms", kKCBeepFrequency, kKCBeepSeconds * 1000);
}

- (void)playBeep {
    if (!self.audioReady) [self prepareAudio];
    if (!self.audioReady) return;
    NSError *err = nil;
    if (![[AVAudioSession sharedInstance] setActive:YES error:&err]) {
        KCLogf(@"alert: setActive loi %@", err);
        return;
    }
    if (!self.engine.isRunning) {
        if (![self.engine startAndReturnError:&err]) {
            KCLogf(@"alert: khong khoi dong duoc audio engine: %@", err);
            return;
        }
    }
    [self.player scheduleBuffer:self.beepBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
    if (!self.player.isPlaying) [self.player play];
}

#pragma mark - Cảnh báo

- (BOOL)fireAlertWithSpokenText:(NSString *)text {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.lastFire > 0 && (now - self.lastFire) < self.minimumInterval) return NO;
    self.lastFire = now;
    [self emit:text];
    return YES;
}

- (void)testAlert {
    self.lastFire = CFAbsoluteTimeGetCurrent();
    [self emit:@"Khoảng cách quá gần"];
}

- (void)emit:(NSString *)text {
    if (self.hapticEnabled) {
        [self.feedback prepare];
        [self.feedback notificationOccurred:UINotificationFeedbackTypeError];
    }
    if (self.beepEnabled) [self playBeep];
    if (self.speechEnabled && text.length && self.voice) {
        AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
        u.voice = self.voice;
        u.rate = AVSpeechUtteranceDefaultSpeechRate;
        u.volume = 1.0;
        // Nói sau tiếng bíp một chút để hai thứ không chồng lên nhau.
        u.preUtteranceDelay = self.beepEnabled ? 0.15 : 0.0;
        [self.synth speakUtterance:u];
    }
}

@end
