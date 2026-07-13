import os

enum Log {
    static let app = Logger(subsystem: "com.karan.writerflow", category: "app")
    static let focus = Logger(subsystem: "com.karan.writerflow", category: "focus")
    static let overlay = Logger(subsystem: "com.karan.writerflow", category: "overlay")
    static let engine = Logger(subsystem: "com.karan.writerflow", category: "engine")
    static let store = Logger(subsystem: "com.karan.writerflow", category: "store")
}
