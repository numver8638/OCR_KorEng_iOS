//
//  OpenCVWrapper.h
//  OCR_KorEng_iOS
//
//  Created by numver8638 on 2021/05/21.
//

#ifndef OpenCVWrapper_h
#define OpenCVWrapper_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface OpenCVWrapper : NSObject

+ (NSString* __nonnull) version;

+ (void) process: (UIImage* __nonnull) input outData: (NSMutableArray* __nonnull  __autoreleasing * __nonnull) datas outRect: (NSMutableArray* __nonnull __autoreleasing * __nonnull) rects;

+ (UIImage* __nonnull) processTest: (UIImage* __nonnull) input;

@end

#endif /* OpenCVWrapper_h */
