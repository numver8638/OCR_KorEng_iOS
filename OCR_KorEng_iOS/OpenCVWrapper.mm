//
//  OpenCVWrapper.mm
//  OCR_KorEng_iOS
//
//  Created by numver8638 on 2021/05/21.
//

#import "OpenCVWrapper.h"

#include <opencv2/imgcodecs/ios.h>

#define MAX_PIXEL_COUNT (1024)

static cv::Mat ConvertImage(const UIImage* input)
{
    cv::Mat output;
    
    UIImageToMat(input, output);
    
    if (output.rows > MAX_PIXEL_COUNT || output.cols > MAX_PIXEL_COUNT) {
        auto scale = MAX_PIXEL_COUNT / (double)std::max(output.rows, output.cols);
        
        cv::resize(output, output, cv::Size(output.cols * scale, output.rows * scale));
    }
    
    cv::cvtColor(output, output, cv::COLOR_RGB2GRAY);
    cv::threshold(output, output, 0, 255.0, cv::THRESH_BINARY_INV|cv::THRESH_OTSU);
    
    return output;
}

static inline bool IsOverlapped(cv::Rect2i left, cv::Rect2i right) {
    if (left.x > right.x) {
        std::swap(left, right);
    }
    
    if ((left.x + left.width) < right.x || (left.y + left.height) < right.y || left.y > (right.y + right.height)) {
        // Not overlapped.
        return false;
    }
    else if ((left.x + left.width) > (right.x + right.width) && left.y < right.y && (left.y + left.height) > (right.y + right.height)) {
        // Contains
        return true;
    }
    else {
        // Overlapped
        return true;
    }
}

static std::vector<cv::Rect2i> GetCharAreas(const cv::Mat& image)
{
    std::vector<cv::Rect2i> target;
    cv::Mat labels, stats, centeroids;
    
    auto labelCount = cv::connectedComponentsWithStats(image, labels, stats, centeroids);
    
    for (auto i = 1; i < labelCount; i++) {
        auto x = stats.at<int>(i, cv::CC_STAT_LEFT);
        auto y = stats.at<int>(i, cv::CC_STAT_TOP);
        auto w = stats.at<int>(i, cv::CC_STAT_WIDTH);
        auto h = stats.at<int>(i, cv::CC_STAT_HEIGHT);
        
        target.emplace_back(x, y-5, w, h+10);
    }
    
    auto loop = true;
    while (loop) {
        loop = false;
        
        for (auto current = target.begin(); current != target.end(); ++current) {
            if (current->width == 0) continue;
            
            for (auto next = target.begin(); next != target.end(); ++next) {
                if (next == current || next->width == 0) continue;
                
                if (IsOverlapped(*current, *next)) {
                    loop = true;
                    
                    auto x = std::min(current->x, next->x);
                    auto y = std::min(current->y, next->y);
                    auto w = std::max(current->br().x, next->br().x) - x;
                    auto h = std::max(current->br().y, next->br().y) - y;
    
                    *current = cv::Rect2i(x, y, w, h);
    
                    next->width = 0;
                }
            }
        }
        
        target.erase(std::remove_if(target.begin(), target.end(), [](const cv::Rect2i& rect) { return rect.width == 0; }), target.end());
    }
    
    target.erase(std::remove_if(target.begin(), target.end(), [](const cv::Rect2i& rect) {
        return rect.width < 5 || rect.height < 5 || rect.x < 0 || rect.y < 0;
    }), target.end());
    
    return target;
}

@implementation OpenCVWrapper

+ (NSString*) version
{
    return [NSString stringWithUTF8String: CV_VERSION];
}

+ (void) process: (UIImage*)input outData: (NSMutableArray **)dataOut outRect: (NSMutableArray **)rectOut
{
    // Convert image to binarized image.
    auto image = ConvertImage(input);
    auto rects = GetCharAreas(image);
    
    for (const auto& rect : rects) {
        cv::Mat roi = image(cv::Rect2i(rect.x, rect.y + 5, rect.width, rect.height - 10));
        
        if (roi.rows > 28 || roi.cols > 28) {
            auto scale = 28 / (double)std::max(roi.rows, roi.cols);
            
            auto size = cv::Size(roi.cols * scale, roi.rows * scale);
            
            if (size.width == 0 || size.height == 0) {
                continue;
            }
            
            cv::resize(roi, roi, size);
        }
        
        auto top = (32 - roi.rows) / 2;
        auto left = (32 - roi.cols) / 2;
        auto bottom = 32 - (roi.rows + top);
        auto right = 32 - (roi.cols + left);
        
        cv::copyMakeBorder(roi, roi, top, bottom, left, right, cv::BORDER_CONSTANT, cv::Scalar(0,0,0));
        
        roi.convertTo(roi, CV_32F, 1 / 255.0, 0);
        
        NSMutableData* data = [[NSMutableData alloc]
                               initWithBytes: roi.data
                               length: roi.total() * roi.elemSize()];
        
        [*dataOut addObject: data];
        [*rectOut addObject: [NSNumber numberWithInt: rect.x]];
        [*rectOut addObject: [NSNumber numberWithInt: rect.y]];
        [*rectOut addObject: [NSNumber numberWithInt: rect.width]];
        [*rectOut addObject: [NSNumber numberWithInt: rect.height]];
    }
}

+ (UIImage*) processTest: (UIImage*) input
{
    cv::Mat output;
    UIImageToMat(input, output);
    
    if (output.rows > MAX_PIXEL_COUNT || output.cols > MAX_PIXEL_COUNT) {
        auto scale = MAX_PIXEL_COUNT / (double)std::max(output.rows, output.cols);
        
        cv::resize(output, output, cv::Size(output.cols * scale, output.rows * scale));
    }
    
    auto image = ConvertImage(input);
    auto rects = GetCharAreas(image);
    
    for (const auto& rect : rects) {
        cv::rectangle(output, rect, cv::Scalar(0,0,255), 1);
    }
    
    return MatToUIImage(output);
}

@end
