/*
 * ZipArchiveReader.swift
 * CameraAccess
 *
 * Pure Swift zip extraction for iOS without external dependencies.
 * Uses the Compression framework and manual ZIP format parsing.
 */

import Foundation
import Compression

// MARK: - Safe Data Extension for Reading Little-Endian Values

private extension Data {
    /// Safely read a UInt16 at the given offset (little-endian)
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    
    /// Safely read a UInt32 at the given offset (little-endian)
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }
}

/// A simple ZIP archive reader for extracting .zip files on iOS
/// Handles the basic ZIP format used by standard archives
final class ZipArchiveReader {
    
    private let fileHandle: FileHandle
    private let fileURL: URL
    private var entries: [ZipEntry] = []
    
    struct ZipEntry {
        let fileName: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16
        let localHeaderOffset: UInt32
        let isDirectory: Bool
    }
    
    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        self.fileURL = url
        self.fileHandle = handle
        
        do {
            try parseEntries()
        } catch {
            print("Failed to parse ZIP: \(error)")
            return nil
        }
    }
    
    deinit {
        try? fileHandle.close()
    }
    
    /// Parse the central directory to find all entries
    private func parseEntries() throws {
        // Find End of Central Directory (EOCD)
        try fileHandle.seekToEnd()
        let fileSize = try fileHandle.offset()
        
        // EOCD is at least 22 bytes, search backwards for signature
        let searchSize = min(fileSize, 65557) // Max comment size + EOCD size
        let searchStart = fileSize - searchSize
        try fileHandle.seek(toOffset: searchStart)
        
        guard let searchData = try fileHandle.read(upToCount: Int(searchSize)) else {
            throw ZipError.invalidArchive
        }
        
        // Find EOCD signature (0x06054b50)
        var eocdOffset: Int? = nil
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        
        for i in stride(from: searchData.count - 22, through: 0, by: -1) {
            if searchData[i] == signature[0] &&
               searchData[i+1] == signature[1] &&
               searchData[i+2] == signature[2] &&
               searchData[i+3] == signature[3] {
                eocdOffset = i
                break
            }
        }
        
        guard let offset = eocdOffset else {
            throw ZipError.invalidArchive
        }
        
        // Parse EOCD using safe reads
        let eocd = searchData.subdata(in: offset..<min(offset+22, searchData.count))
        let centralDirOffset = eocd.readUInt32(at: 16)
        let centralDirSize = eocd.readUInt32(at: 12)
        let entryCount = eocd.readUInt16(at: 10)
        
        // Read central directory
        try fileHandle.seek(toOffset: UInt64(centralDirOffset))
        guard let centralDir = try fileHandle.read(upToCount: Int(centralDirSize)) else {
            throw ZipError.invalidArchive
        }
        
        // Parse each central directory entry
        var pos = 0
        for _ in 0..<entryCount {
            guard pos + 46 <= centralDir.count else { break }
            
            // Verify signature (0x02014b50)
            guard centralDir[pos] == 0x50 && centralDir[pos+1] == 0x4b && 
                  centralDir[pos+2] == 0x01 && centralDir[pos+3] == 0x02 else {
                break
            }
            
            let compressionMethod = centralDir.readUInt16(at: pos + 10)
            let compressedSize = centralDir.readUInt32(at: pos + 20)
            let uncompressedSize = centralDir.readUInt32(at: pos + 24)
            let fileNameLength = Int(centralDir.readUInt16(at: pos + 28))
            let extraFieldLength = Int(centralDir.readUInt16(at: pos + 30))
            let commentLength = Int(centralDir.readUInt16(at: pos + 32))
            let localHeaderOffset = centralDir.readUInt32(at: pos + 42)
            
            pos += 46
            
            guard pos + fileNameLength <= centralDir.count else { break }
            
            let fileNameData = centralDir.subdata(in: pos..<pos+fileNameLength)
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""
            
            pos += fileNameLength + extraFieldLength + commentLength
            
            let entry = ZipEntry(
                fileName: fileName,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset,
                isDirectory: fileName.hasSuffix("/")
            )
            entries.append(entry)
        }
    }
    
    /// Extract all entries to the destination directory
    func extractAll(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        for entry in entries {
            let destPath = destinationURL.appendingPathComponent(entry.fileName)
            
            if entry.isDirectory {
                try fileManager.createDirectory(at: destPath, withIntermediateDirectories: true)
            } else {
                // Ensure parent directory exists
                try fileManager.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                
                // Extract file
                let data = try extractEntry(entry)
                try data.write(to: destPath)
            }
        }
    }
    
    /// Extract a single entry
    private func extractEntry(_ entry: ZipEntry) throws -> Data {
        // Seek to local header
        try fileHandle.seek(toOffset: UInt64(entry.localHeaderOffset))
        
        // Read local header (30 bytes minimum)
        guard let localHeader = try fileHandle.read(upToCount: 30) else {
            throw ZipError.invalidArchive
        }
        
        // Verify signature (0x04034b50)
        guard localHeader[0] == 0x50 && localHeader[1] == 0x4b && 
              localHeader[2] == 0x03 && localHeader[3] == 0x04 else {
            throw ZipError.invalidArchive
        }
        
        let fileNameLength = Int(localHeader.readUInt16(at: 26))
        let extraFieldLength = Int(localHeader.readUInt16(at: 28))
        
        // Skip file name and extra field
        let skipBytes = fileNameLength + extraFieldLength
        _ = try fileHandle.read(upToCount: skipBytes)
        
        // Read compressed data
        guard let compressedData = try fileHandle.read(upToCount: Int(entry.compressedSize)) else {
            throw ZipError.invalidArchive
        }
        
        // Decompress if needed
        switch entry.compressionMethod {
        case 0: // Stored (no compression)
            return compressedData
        case 8: // Deflate
            return try decompressDeflate(compressedData, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupportedCompression
        }
    }
    
    /// Decompress deflate-compressed data
    private func decompressDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        // Add extra buffer space for safety
        let bufferSize = max(expectedSize, data.count * 4)
        var decompressed = Data(count: bufferSize)
        
        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        guard result > 0 else {
            throw ZipError.decompressionFailed
        }
        
        return Data(decompressed.prefix(result))
    }
    
    enum ZipError: LocalizedError {
        case invalidArchive
        case unsupportedCompression
        case decompressionFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Invalid or corrupted ZIP archive"
            case .unsupportedCompression: return "Unsupported compression method"
            case .decompressionFailed: return "Failed to decompress data"
            }
        }
    }
}
