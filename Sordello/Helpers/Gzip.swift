//
//  Gzip.swift
//  Sordello
//
//  Created by Jonas Barsten on 09/12/2025.
//

import Foundation
import Compression

extension Data {
    /// Decompress gzip data
    /// nonisolated: Pure data transformation, safe to call from background threads
    nonisolated func gunzip() -> Data? {
        guard self.count > 10, self[0] == 0x1f, self[1] == 0x8b else { return nil }
        
        var offset = 10
        let flags = self[3]
        
        if (flags & 0x04) != 0 && offset + 2 <= self.count {
            let extraLen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + extraLen
        }
        if (flags & 0x08) != 0 {
            while offset < self.count && self[offset] != 0 { offset += 1 }
            offset += 1
        }
        if (flags & 0x10) != 0 {
            while offset < self.count && self[offset] != 0 { offset += 1 }
            offset += 1
        }
        
        guard offset < self.count - 8 else { return nil }
        
        let sizeOffset = self.count - 4
        let originalSize = Int(self[sizeOffset]) |
        (Int(self[sizeOffset + 1]) << 8) |
        (Int(self[sizeOffset + 2]) << 16) |
        (Int(self[sizeOffset + 3]) << 24)
        
        let compressedData = self.subdata(in: offset..<(self.count - 8))
        let bufferSize = originalSize + 1024
        
        return compressedData.withUnsafeBytes { srcPtr -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            let size = compression_decode_buffer(
                buffer, bufferSize,
                srcBase.assumingMemoryBound(to: UInt8.self), compressedData.count,
                nil, COMPRESSION_ZLIB
            )
            
            return size > 0 ? Data(bytes: buffer, count: size) : nil
        }
    }
}
