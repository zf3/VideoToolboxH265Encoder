//
//  CVPixelBuffer+Extension.swift
//  VideoToolboxCompression
//
//  Created by tomisacat on 14/08/2017.
//  Copyright © 2017 tomisacat. All rights reserved.
//

import Foundation
import VideoToolbox
import CoreVideo

extension CVPixelBuffer {
    public enum LockFlag {
        case readwrite
        case readonly
        
        func flag() -> CVPixelBufferLockFlags {
            switch self {
            case .readonly:
                return .readOnly
            default:
                return CVPixelBufferLockFlags.init(rawValue: 0)
            }
        }
    }
    
    public func lock(_ flag: LockFlag, closure: (() -> Void)?) {
        if CVPixelBufferLockBaseAddress(self, flag.flag()) == kCVReturnSuccess {
            if let c = closure {
                c()
            }
        }
        
        CVPixelBufferUnlockBaseAddress(self, flag.flag())
    }
}
