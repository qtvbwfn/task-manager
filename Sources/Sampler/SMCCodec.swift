import Foundation

/// SMC 数值解码（key TC0P 等使用 sp78 定点格式）。
enum SMCCodec {
    /// sp78：高字节 = 整数部分（有符号），低字节 = 小数部分（1/256）
    static func decodeSP78(_ bytes: [UInt8]) -> Double {
        guard bytes.count >= 2 else { return .nan }
        return Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256.0
    }
}