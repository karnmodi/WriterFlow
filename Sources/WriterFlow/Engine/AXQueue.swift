import Foundation

/// The one background queue on which all AX IO happens.
/// Off-main, so an unresponsive host app cannot beach-ball WriterFlow.
enum AXQueue {
    static let shared = DispatchQueue(label: "com.karan.writerflow.axio", qos: .userInitiated)
}
