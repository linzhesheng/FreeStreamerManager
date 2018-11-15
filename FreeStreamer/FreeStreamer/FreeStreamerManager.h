//
//  FreeStreamerManager.h
//  academy
//
//  Created by licc on 2017/12/7.
//  Copyright © 2017年 JZ-jingzhuan. All rights reserved.
//

#import <UIKit/UIKit.h>

#define kControlAudioPauseNotification @"kControlAudioPauseNotification" // 控制中心音乐已经暂停
#define kControlAudioPlayNotification @"kControlAudioPlayNotification" // 控制中心音乐已经播放

typedef NS_ENUM(NSInteger,FreeStreamerManagerState)
{
    FreeStreamerManagerStatePause = 1,
    FreeStreamerManagerStatePlaying,
    FreeStreamerManagerStateStop,
    FreeStreamerManagerStateBuffering,
    FreeStreamerManagerStateFailed,
    FreeStreamerManagerStateCompleted,
    FreeStreamerManagerStateSeeking
};

@protocol FreeStreamerManagerDelegate<NSObject>
//当前播放时间已经改变
- (void)currentTimeDidChanged:(NSInteger)currentTime;
//缓冲进度
- (void)progressBufferDidChanged:(float)progress;
//刚开始播放时的定位
- (void)beginSeekTimeToPlay:(NSInteger)seekTime;

@end

@class FreeStreamerModel;
@interface FreeStreamerManager : NSObject

@property(nonatomic,strong,readonly)FreeStreamerModel *model;
//总时长
@property(nonatomic,assign,readonly)NSInteger duration;
//当前播放的时间
@property(nonatomic,assign,readonly)NSInteger currentTime;
//缓冲比率
@property(nonatomic,assign,readonly)float bufferingRatio;
//状态
@property(nonatomic,assign,readonly)FreeStreamerManagerState state;

@property(nonatomic,weak)id<FreeStreamerManagerDelegate> delegate;

+ (instancetype)shareInstance;

//开始
- (void)beginWithModel:(FreeStreamerModel *)model seekTime:(NSInteger)seekTime;
//结束
- (void)stop;
//播放
- (void)play;
//从指定时间开始播放
- (void)playFromTime:(NSInteger)time;
//暂停
- (void)pause;

@end

// ---------------- FreeStreamerModel ----------------

@interface FreeStreamerModel : NSObject

@property(nonatomic,strong)NSString *urlString; // 资源链接
// ---- 用于控制中心的显示 ----
@property(nonatomic,strong)NSString *coverImg; // 封面图片，链接
@property(nonatomic,strong)UIImage *localCoverImg; // 本地图片，如果设置了该字段，coverImg会无效
@property(nonatomic,strong)NSString *title; // 资源名
@property(nonatomic,strong)NSString *author; // 作者

@end






