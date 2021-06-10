//
//  Recognizer.swift
//  OCR_KorEng_iOS
//
//  Created by numver8638 on 2021/05/21.
//

import Foundation
import TensorFlowLite
import TensorFlowLiteCMetal
import TensorFlowLiteCCoreML

struct Rect : Comparable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    
    var right: Int {
        get { x + width }
    }
    
    var bottom: Int {
        get { y + height }
    }
    
    init() {
        self.init(x: 0, y: 0, width: 0, height: 0)
    }
    
    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    static func < (lhs: Rect, rhs: Rect) -> Bool {
        if lhs.bottom <= rhs.y {
            return true
        } else {
            return lhs.x < rhs.x
        }
    }
    
}

class Recognizer {
    private let interpreter: Interpreter
    private let labels: [String]
    
    fileprivate init?(modelPath: String, labelPath: String) {
        do {
            // Initialize interpreter
            // Try use CoreML if can.
            if let coremlDelegate = CoreMLDelegate() {
                print("use CoreML delegate.")
                self.interpreter = try Interpreter(modelPath: modelPath, delegates: [coremlDelegate])
            }
            else {
                // Fallback to GPU.
                print("use Metal delegate.")
                let metalDelegate = MetalDelegate()
                self.interpreter = try Interpreter(modelPath: modelPath, delegates: [metalDelegate])
            }
            
            try interpreter.allocateTensors()
            
            // Load labels
            let contents = try String(contentsOf: URL(fileURLWithPath: labelPath))
            
            self.labels = contents.components(separatedBy: .newlines)
        } catch let error {
            debugPrint("Failed to initalize Recognizer: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func newInstance(completion: @escaping (Recognizer) -> Void,
                            onFailure: @escaping (InitError) -> Void) {
        DispatchQueue.global(qos: .background).async {
            guard let modelPath = Bundle.main.path(forResource: "model", ofType: "tflite"),
                  let labelPath = Bundle.main.path(forResource: "labels", ofType: "txt") else {
                DispatchQueue.main.async {
                    onFailure(.invalidData)
                }
                return
            }
            
            DispatchQueue.main.async {
                if let instance = Recognizer(modelPath: modelPath, labelPath: labelPath) {
                    completion(instance)
                } else {
                    onFailure(.failedToCreateInterpreter)
                }
            }
        }
    }
    
    func recognize(input: UIImage, progress: Progress,
                   completion: @escaping (RecognizeResult) -> Void,
                   onFailure: @escaping (RecognitionError) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // Process image
            var datas = NSMutableArray()
            var rawRects = NSMutableArray()
            var rects = [Rect]()
            
            OpenCVWrapper.process(input, outData: &datas, outRect: &rawRects)
            
            assert(rawRects.count % 4 == 0)
            assert(datas.count == (rawRects.count / 4))
            
            if datas.count == 0 {
                DispatchQueue.main.async {
                    onFailure(.unreconizableImage)
                }
                return
            }
            
            for i in 0..<(rawRects.count / 4) {
                let x = Int(exactly: rawRects[i * 4 + 0] as! NSNumber)!
                let y = Int(exactly: rawRects[i * 4 + 1] as! NSNumber)!
                let width = Int(exactly: rawRects[i * 4 + 2] as! NSNumber)!
                let height = Int(exactly: rawRects[i * 4 + 3] as! NSNumber)!
                
                rects.append(Rect(x: x, y: y, width: width, height: height))
            }
            
            var sum: Double = 0.0
            var minConfidence: Float = 1.0 // Never exceeds 1.0
            var maxConfidence: Float = 0.0
            var converted = [(String, Rect)]()
            
            // Classify image
            for (data, rect) in zip(datas, rects) {
                if progress.isCancelled { break }
                
                let result: [Float]
                
                do {
                    try self.interpreter.copy(data as! Data, toInputAt: 0)
                    try self.interpreter.invoke()
                    
                    let outputTensor = try self.interpreter.output(at: 0)
                    result = [Float](withData: outputTensor.data)!
                } catch let error {
                    DispatchQueue.main.async { onFailure(.interpreterError(error: error)) }
                    return
                }
                
                let index = result.argmax()
                let confidence = result[index]
                
                converted.append((self.labels[index], rect))
                
                sum += Double(confidence)
                minConfidence = min(minConfidence, confidence)
                maxConfidence = max(maxConfidence, confidence)
            }
            
            // Sort characters by position
            converted.sort { $0.1 < $1.1 }

            var text = ""
            var prevRect = Rect()
            converted.forEach { (ch, rect) in
                if (prevRect.bottom < rect.y) {
                    text.append("\n")
                }

                text.append(ch)
                prevRect = rect
            }

            DispatchQueue.main.async {
                completion(RecognizeResult(text: text,
                                           confidence: Float(sum / Double(datas.count)),
                                           maxConfidence: maxConfidence,
                                           minConfidence: minConfidence))
            }
        }
    }
}

extension Array {
    init?(withData data: Data) {
        guard data.count % MemoryLayout<Element>.stride == 0 else { return nil }
        
        self = data.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
    }
}

extension Array where Element == Float {
    func argmax() -> Int {
        var index = 0
        var max_index = 0
        var max_arg: Float = 0
        for arg in self {
            if max_arg < arg {
                max_index = index
                max_arg = arg
            }
            
            index += 1
        }
        
        return self.count > 0 ? max_index : -1
    }
}

struct RecognizeResult {
    let text: String
    let confidence: Float
    let maxConfidence: Float
    let minConfidence: Float
}

enum RecognitionError: Error {
    case unreconizableImage
    case preprocessError(error: Error)
    case interpreterError(error: Error)
}

enum InitError: Error {
    case invalidData
    case failedToCreateInterpreter
    case internalError(error: Error)
}
