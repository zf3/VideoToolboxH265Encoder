//
//  ViewController.swift
//  VideoToolboxCompression
//
//  Created by tomisacat on 12/08/2017.
//  Copyright © 2017 tomisacat. All rights reserved.
//

import UIKit
import AVFoundation
import VideoToolbox

fileprivate var NALUHeader: [UInt8] = [0, 0, 0, 1]

func compressionOutputCallback(outputCallbackRefCon: UnsafeMutableRawPointer?,
                               sourceFrameRefCon: UnsafeMutableRawPointer?,
                               status: OSStatus,
                               infoFlags: VTEncodeInfoFlags,
                               sampleBuffer: CMSampleBuffer?) -> Swift.Void {
    guard status == noErr else {
        print("error: \(status)")
        return
    }
    
    if infoFlags == .frameDropped {
        print("frame dropped")
        return
    }
    
    guard let sampleBuffer = sampleBuffer else {
        print("sampleBuffer is nil")
        return
    }
    
    if CMSampleBufferDataIsReady(sampleBuffer) != true {
        print("sampleBuffer data is not ready")
        return
    }
    
//    let desc = CMSampleBufferGetFormatDescription(sampleBuffer)
//    let extensions = CMFormatDescriptionGetExtensions(desc!)
//    print("extensions: \(extensions!)")
//
//    let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
//    print("sample count: \(sampleCount)")
//
//    let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
//    var length: Int = 0
//    var dataPointer: UnsafeMutablePointer<Int8>?
//    CMBlockBufferGetDataPointer(dataBuffer, 0, nil, &length, &dataPointer)
//    print("length: \(length), dataPointer: \(dataPointer!)")
    
    let vc: ViewController = Unmanaged.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true) {
        print("attachments: \(attachments)")
        
        let rawDic: UnsafeRawPointer = CFArrayGetValueAtIndex(attachments, 0)
        let dic: CFDictionary = Unmanaged.fromOpaque(rawDic).takeUnretainedValue()
        
        // if not contains means it's an IDR frame
        let keyFrame = !CFDictionaryContainsKey(dic, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        if keyFrame {
            print("IDR frame")
            
            // sps
            let format = CMSampleBufferGetFormatDescription(sampleBuffer)
            var spsSize: Int = 0
            var spsCount: Int = 0
            var nalHeaderLength: Int32 = 0
            var sps: UnsafePointer<UInt8>?
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                  0,
                                                                  &sps,
                                                                  &spsSize,
                                                                  &spsCount,
                                                                  &nalHeaderLength) == noErr {
                print("sps: \(String(describing: sps)), spsSize: \(spsSize), spsCount: \(spsCount), NAL header length: \(nalHeaderLength)")
                
                // pps
                var ppsSize: Int = 0
                var ppsCount: Int = 0
                var pps: UnsafePointer<UInt8>?
                
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                      1,
                                                                      &pps,
                                                                      &ppsSize,
                                                                      &ppsCount,
                                                                      &nalHeaderLength) == noErr {
                    print("sps: \(String(describing: pps)), spsSize: \(ppsSize), spsCount: \(ppsCount), NAL header length: \(nalHeaderLength)")
                    
                    let spsData: NSData = NSData(bytes: sps, length: spsSize)
                    let ppsData: NSData = NSData(bytes: pps, length: ppsSize)
                    
                    vc.handle(sps: spsData, pps: ppsData)
                }
            }
        } // end of handle sps/pps
        
        // handle frame data
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(dataBuffer, 0, &lengthAtOffset, &totalLength, &dataPointer) == noErr {
            var bufferOffset: Int = 0
            let AVCCHeaderLength = 4
            
            while bufferOffset < (totalLength - AVCCHeaderLength) {
                var NALUnitLength: UInt32 = 0
                // first four character is NALUnit length
                memcpy(&NALUnitLength, dataPointer?.advanced(by: bufferOffset), AVCCHeaderLength)
                
                // big endian to host endian. in iOS it's little endian
                NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
                
                let data: NSData = NSData(bytes: dataPointer?.advanced(by: bufferOffset + AVCCHeaderLength), length: Int(NALUnitLength))
                vc.encode(data: data, isKeyFrame: keyFrame)
                
                // move forward to the next NAL Unit
                bufferOffset += Int(AVCCHeaderLength)
                bufferOffset += Int(NALUnitLength)
            }
        }
    }
}

class ViewController: UIViewController {
    
    let captureSession = AVCaptureSession()
    let captureQueue = DispatchQueue(label: "videotoolbox.compression.capture")
    let compressionQueue = DispatchQueue(label: "videotoolbox.compression.compression")
    lazy var preview: AVCaptureVideoPreviewLayer = {
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        
        return preview
    }()
    
    var compressionSession: VTCompressionSession?
    var fileHandler: FileHandle?
    var isCapturing: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let path = NSTemporaryDirectory() + "/temp.h264"
        try? FileManager.default.removeItem(atPath: path)
        if FileManager.default.createFile(atPath: path, contents: nil, attributes: nil) {
            fileHandler = FileHandle(forWritingAtPath: path)
        }
        
        let device = AVCaptureDevice.default(for: .video)!
        let input = try! AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        captureSession.sessionPreset = .high
        let output = AVCaptureVideoDataOutput()
        // YUV 420v
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
        
        // not a good method
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!
            }
        }
        
        captureSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        preview.frame = view.bounds
        
        let button = UIButton(type: .roundedRect)
        button.setTitle("Click Me", for: .normal)
        button.backgroundColor = .red
        button.addTarget(self, action: #selector(startOrNot), for: .touchUpInside)
        button.frame = CGRect(x: 100, y: 200, width: 100, height: 40)

        view.addSubview(button)
    }
}

extension ViewController {
    @objc func startOrNot() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }
    
    func startCapture() {
        isCapturing = true
    }
    
    func stopCapture() {
        isCapturing = false
        
        guard let compressionSession = compressionSession else {
            return
        }
        
        VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid)
        VTCompressionSessionInvalidate(compressionSession)
        self.compressionSession = nil
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelbuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
//        if CVPixelBufferIsPlanar(pixelbuffer) {
//            print("planar: \(CVPixelBufferGetPixelFormatType(pixelbuffer))")
//        }
//
//        var desc: CMFormatDescription?
//        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelbuffer, &desc)
//        let extensions = CMFormatDescriptionGetExtensions(desc!)
//        print("extensions: \(extensions!)")
        
        if compressionSession == nil {
            let width = CVPixelBufferGetWidth(pixelbuffer)
            let height = CVPixelBufferGetHeight(pixelbuffer)
            
            print("width: \(width), height: \(height)")

            VTCompressionSessionCreate(kCFAllocatorDefault,
                                       Int32(width),
                                       Int32(height),
                                       kCMVideoCodecType_H264,
                                       nil, nil, nil,
                                       compressionOutputCallback,
                                       UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                       &compressionSession)
            
            guard let c = compressionSession else {
                return
            }
            
            // set profile to Main
            VTSessionSetProperty(c, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
            // capture from camera, so it's real time
            VTSessionSetProperty(c, kVTCompressionPropertyKey_RealTime, true as CFTypeRef)
            // 关键帧间隔
            VTSessionSetProperty(c, kVTCompressionPropertyKey_MaxKeyFrameInterval, 10 as CFTypeRef)
            // 比特率和速率
            VTSessionSetProperty(c, kVTCompressionPropertyKey_AverageBitRate, width * height * 2 * 32 as CFTypeRef)
            VTSessionSetProperty(c, kVTCompressionPropertyKey_DataRateLimits, [width * height * 2 * 4, 1] as CFArray)
            
            VTCompressionSessionPrepareToEncodeFrames(c)
        }
        
        guard let c = compressionSession else {
            return
        }
        
        guard isCapturing else {
            return
        }
        
        compressionQueue.sync {
            pixelbuffer.lock(.readwrite) {
                let presentationTimestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                let duration = CMSampleBufferGetOutputDuration(sampleBuffer)
                VTCompressionSessionEncodeFrame(c, pixelbuffer, presentationTimestamp, duration, nil, nil, nil)
            }
        }
    }
    
    func handle(sps: NSData, pps: NSData) {
        guard let fh = fileHandler else {
            return
        }
        
        let headerData: NSData = NSData(bytes: NALUHeader, length: NALUHeader.count)
        fh.write(headerData as Data)
        fh.write(sps as Data)
        fh.write(headerData as Data)
        fh.write(pps as Data)
    }
    
    func encode(data: NSData, isKeyFrame: Bool) {
        guard let fh = fileHandler else {
            return
        }
        
        let headerData: NSData = NSData(bytes: NALUHeader, length: NALUHeader.count)
        fh.write(headerData as Data)
        fh.write(data as Data)
    }
}

