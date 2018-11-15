//
//  FreeStreamerManager.m
//  academy
//
//  Created by licc on 2017/12/7.
//  Copyright © 2017年 JZ-jingzhuan. All rights reserved.
//

#import "FreeStreamerManager.h"
#import "FSAudioStream.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface FreeStreamerManager()

//这个属性指向的对象也是只创建一次，随单例
@property(nonatomic,strong)FSAudioStream *audioStream;
//获取播放进度和缓存进度用
@property(nonatomic,strong)NSTimer *audioStreamTimer;
// 时间点控制
@property(nonatomic,assign)NSInteger beginSeekTime;
@property(nonatomic,assign)NSInteger slideSeekTime;
@property(nonatomic,assign)NSInteger slideReplaySeekTime;
@property(nonatomic,assign)NSInteger slideSeekTime2;

@property(nonatomic,strong)FreeStreamerModel *model;
//通过set方法赋值，外界使用KVO可观察
@property(nonatomic,assign)NSInteger duration;
@property(nonatomic,assign)NSInteger currentTime;
@property(nonatomic,assign)float bufferingRatio;
@property(nonatomic,assign)FreeStreamerManagerState state;

//是否是控制中心拖动
@property(nonatomic,assign)BOOL isControlCenterSlide;
//控制中心歌曲信息
@property (copy, nullable) NSMutableDictionary<NSString *, id> *songInfo;
//中断事件判断
@property(nonatomic,assign)BOOL played;

@end

@implementation FreeStreamerManager

+(instancetype)shareInstance {
    static FreeStreamerManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [FreeStreamerManager new];
        [manager setupSelf];
    });
    
    return manager;
}

- (void)setupSelf {
    FSStreamConfiguration *configuration = [FSStreamConfiguration new];
    configuration.maxDiskCacheSize = 77137376;
    configuration.maxPrebufferedByteCount = 77137376;
    
    _audioStream = [[FSAudioStream alloc] initWithConfiguration:configuration];
    
    self.state = FreeStreamerManagerStateStop;
}

#pragma mark - 开始
- (void)beginWithModel:(FreeStreamerModel *)model seekTime:(NSInteger)seekTime {
    //停止之前的播放，并将所有属性置空
    [self stop];
    
    if (!model.urlString.length) {
        return;
    }
    
    _model = model;
    _beginSeekTime = seekTime;
    // 控制中心设置
    [self setupAudioControl];
    
    _audioStream.url = [NSURL URLWithString:model.urlString];
    __weak typeof(self) weakSelf = self;
    _audioStream.onStateChange = ^(FSAudioStreamState state) {
        switch (state) {
            case kFsAudioStreamPlaying:
            {
                if (!weakSelf.duration) {
                    [weakSelf firstPlaySetting];
                } else {
                    //没有播放，然后进入该方法时，audioStream.currentTimePlayed.playbackTimeInSeconds取到0，不应该在这里对self.currentTime赋值
//                    self.currentTime = _audioStream.currentTimePlayed.playbackTimeInSeconds;
                    weakSelf.state = FreeStreamerManagerStatePlaying;
                    
                    if (weakSelf.beginSeekTime) {
                        [weakSelf AudioControlProgressIsGo:YES settingTime:weakSelf.beginSeekTime];
                        weakSelf.beginSeekTime = 0;
                    } else if (weakSelf.slideSeekTime) {
                        [weakSelf AudioControlProgressIsGo:YES settingTime:weakSelf.slideSeekTime];
                        weakSelf.slideSeekTime = 0;
                    } else {
                        [weakSelf AudioControlProgressIsGo:YES settingTime:weakSelf.currentTime];
                    }
                    
                    //是否是重播的时候一开始拖动了进度条
                    if (weakSelf.slideReplaySeekTime) {
                        [weakSelf playFromTime:weakSelf.slideReplaySeekTime];
                        [weakSelf AudioControlProgressIsGo:YES settingTime:weakSelf.slideReplaySeekTime];
                        weakSelf.slideReplaySeekTime = 0;
                    }
                }
            }
                break;
                
            case kFsAudioStreamPaused:
            {
                weakSelf.state = FreeStreamerManagerStatePause;
                [weakSelf AudioControlProgressIsGo:NO settingTime:weakSelf.currentTime];
            }
                break;
                
            case kFsAudioStreamBuffering:
            {
                weakSelf.state = FreeStreamerManagerStateBuffering;
//                [self AudioControlProgressIsGo:NO settingTime:self.currentTime];
            }
                break;
            
            case kFSAudioStreamEndOfFile:
            {
                NSLog(@"整个音频缓冲完成");
                
            }
                break;
                
            case kFsAudioStreamPlaybackCompleted:
            {
                weakSelf.slideSeekTime2 = 0;
            }
                break;
                
            case kFsAudioStreamFailed:
            {
                weakSelf.state = FreeStreamerManagerStateFailed;
                
            }
                break;
            default:
                break;
        }
    };
    
    _audioStream.onCompletion = ^{
        weakSelf.state = FreeStreamerManagerStateCompleted;
    };
    
    _audioStream.onFailure = ^(FSAudioStreamError error, NSString *errorDescription) {
        NSLog(@"%@",errorDescription);
        weakSelf.state = FreeStreamerManagerStateFailed;
    };

    [_audioStream play];

    //后台会话被中断通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterreption:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
}

#pragma mark - 第一次播放时候的设置
- (void)firstPlaySetting {
    self.duration = _audioStream.duration.playbackTimeInSeconds;
    
    //控制中心设置
    [self.songInfo setObject:[NSString stringWithFormat:@"%zd",self.duration] forKey:MPMediaItemPropertyPlaybackDuration];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:self.songInfo];
    
    //监听播放进度和缓冲进度
    if (!_audioStreamTimer) {
        _audioStreamTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(playProgressAndBuffer) userInfo:nil repeats:YES];
    }
    
    //是否有记录
    if (!_beginSeekTime) {
        self.state = FreeStreamerManagerStatePlaying;
        [self AudioControlProgressIsGo:YES settingTime:0];
    } else {
        [self playFromTime:_beginSeekTime];
        if ([self.delegate respondsToSelector:@selector(beginSeekTimeToPlay:)]) {
            [self.delegate beginSeekTimeToPlay:_beginSeekTime];
        }
    }
}

#pragma mark - 监听播放进度和缓冲进度
- (void)playProgressAndBuffer {
    
    if (self.state == FreeStreamerManagerStatePlaying) {
        
        if (_audioStream.currentTimePlayed.playbackTimeInSeconds > _slideSeekTime2) {
            self.currentTime = (NSInteger)_audioStream.currentTimePlayed.playbackTimeInSeconds;
            
        } else {
            self.currentTime = _slideSeekTime2;
        }

        if ([self.delegate respondsToSelector:@selector(currentTimeDidChanged:)]) {
            [self.delegate currentTimeDidChanged:self.currentTime];
        }
        
        //改变缓冲进度
        float  prebuffer = (float)self.audioStream.prebufferedByteCount;
        float contentlength = (float)self.audioStream.contentLength;
//        NSLog(@"%f",contentlength);
//        NSLog(@"%f",prebuffer/contentlength);
        if (contentlength>0) {
            if ([self.delegate respondsToSelector:@selector(progressBufferDidChanged:)]) {
                
                [self.delegate progressBufferDidChanged:prebuffer/contentlength+self.currentTime/_audioStream.duration.playbackTimeInSeconds];
            }
        }
    }
}

#pragma mark - 停止播放
- (void)stop {
    
    [_audioStream stop];
    _audioStream.url = nil;
    
    _duration = 0;
    _currentTime = 0;
    _bufferingRatio = 0.0;
    
    _beginSeekTime = 0;
    _slideSeekTime = 0;
    _slideReplaySeekTime = 0;
    _slideSeekTime2 = 0;
    
    [_audioStreamTimer invalidate];
    _audioStreamTimer = nil;
    
    _state = FreeStreamerManagerStateStop;
    
    _songInfo = nil;
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_songInfo];
}

#pragma mark - 播放
- (void) play {
    if (_audioStream.url && _audioStream.isPlaying == NO) {
        
        if (self.state != FreeStreamerManagerStateCompleted) {
            [_audioStream pause];
        } else {
            [_audioStream play];
        }
    }
}

#pragma mark - 暂停播放
- (void)pause {
    if (_audioStream.url && _audioStream.isPlaying == YES) {
        [_audioStream pause];
    }
}

#pragma mark - 从指定时间开始播放
- (void)playFromTime:(NSInteger)time {
    
    if (_audioStream.url) {
        
        if (_isControlCenterSlide) {
            _isControlCenterSlide = NO;
        } else {
            [self play];
        }
        
        self.currentTime = time;
        _slideSeekTime = time;
        _slideSeekTime2 = time;
        // ?
        self.state = FreeStreamerManagerStateSeeking;
        if (self.state != FreeStreamerManagerStateCompleted) {
            //用户拖动到最后时，时间减掉1秒，否则无法触发_audioStream.onCompletion方法
            if (time == self.duration) {
                time--;
            }
            
            FSStreamPosition position = {};
            position.second = time % 60;
            position.minute = (unsigned int)time / 60;
            position.playbackTimeInSeconds = time;
            position.position = time/_duration;
            [_audioStream seekToPosition:position];
        } else {
            //重播一开始就拖动进度
            _slideReplaySeekTime = time;
            [_audioStream play];
        }
    }
}

#pragma mark - 音乐会话被中断
-(void)handleInterreption:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        //Handle InterruptionBegan
        [self pause];
        [[NSNotificationCenter defaultCenter] postNotificationName:kControlAudioPauseNotification object:self];
    }else{
        AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (options == AVAudioSessionInterruptionOptionShouldResume) {
            //Handle Resume
            [self play];
            [[NSNotificationCenter defaultCenter] postNotificationName:kControlAudioPlayNotification object:self];
        }
    }
}

#pragma mark - 控制中心的设置
- (void)setupAudioControl {
    _songInfo = [NSMutableDictionary new];
    if (_model.localCoverImg) {
        // 本地封面图片
        // 设置封面
        MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithImage:_model.localCoverImg];
        [_songInfo setObject:albumArt forKey:MPMediaItemPropertyArtwork];
    } else if (_model.coverImg) {
        // 网络封面图片
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSData *imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:self.model.coverImg]];
            UIImage *image = [UIImage imageWithData:imgData];
            // 设置封面
            MPMediaItemArtwork *albumArt2 = [[MPMediaItemArtwork alloc] initWithImage:image];
            [self.songInfo setObject:albumArt2 forKey:MPMediaItemPropertyArtwork];
            [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:self.songInfo];
        });
    }
    
    //标题
    [_songInfo setObject:_model.title forKey:MPMediaItemPropertyTitle];
    //作者
    [_songInfo setObject:_model.author forKey:MPMediaItemPropertyArtist];
    //进度光标的速度
    [_songInfo setObject:[NSNumber numberWithFloat:0.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_songInfo];
    
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    //播放
    MPRemoteCommand *playCommand = [commandCenter playCommand];
    playCommand.enabled = YES;
    [playCommand addTarget:self action:@selector(clickPlayCommand:)];
    //暂停
    MPRemoteCommand *pauseCommand = [commandCenter pauseCommand];
    pauseCommand.enabled = YES;
    [pauseCommand addTarget:self action:@selector(clickPauseCommand:)];
    //滑块停止滑动
    MPChangePlaybackPositionCommand *playbackPositionCommand = [commandCenter changePlaybackPositionCommand];
    playbackPositionCommand.enabled = YES;
    [playbackPositionCommand addTarget:self action:@selector(clickPlaybackPositionCommand:)];
    
}

#pragma mark - 秒数转化为时分秒
- (NSString *)timeFormatted:(NSInteger)totalSeconds {
    NSInteger seconds = totalSeconds % 60;
    NSInteger minutes = totalSeconds / 60;
    
    return [NSString stringWithFormat:@"%02zd:%02zd", minutes, seconds];
}

#pragma mark - 控制中心监听方法
- (void)clickPlayCommand:(MPRemoteCommandEvent *)event {
    [self play];
}

- (void)clickPauseCommand:(MPRemoteCommandEvent *)event {
    [self pause];
}

- (void)clickPlaybackPositionCommand:(MPChangePlaybackPositionCommandEvent *)event {
    
    if (self.state == FreeStreamerManagerStatePlaying) {
        _isControlCenterSlide = YES;
    }
    
    [self playFromTime:event.positionTime];
}

#pragma mark - 更新控制中心的当前时间
- (void)updateAudioControlCurrentTime:(NSInteger)currentTime {
    [_songInfo setObject:[NSString stringWithFormat:@"%zd",currentTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_songInfo];
}

#pragma mark - 控制中心的进度条是否走动
- (void)AudioControlProgressIsGo:(BOOL)isGo settingTime:(NSInteger)settingTime {
    if (isGo) {
        [_songInfo setObject:[NSNumber numberWithFloat:1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    } else {
        [_songInfo setObject:[NSNumber numberWithFloat:0.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    }
    [_songInfo setObject:[NSString stringWithFormat:@"%zd",settingTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_songInfo];
}


@end

// ---------------- FreeStreamerModel ----------------

@implementation FreeStreamerModel

@end

