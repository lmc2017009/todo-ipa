import Foundation

/// 高危工具执行前的二次确认
@MainActor
final class ApprovalCenter: ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
        var call: ToolCallRecord
        var detail: String
        var isDangerous: Bool
    }

    @Published private(set) var request: Request?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    func ask(call: ToolCallRecord, detail: String, isDangerous: Bool) async -> Bool {
        if request != nil { return false }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.request = Request(call: call, detail: detail, isDangerous: isDangerous)

            // 两分钟没人处理就当作拒绝
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard self.request != nil else { return }
                self.resolve(false)
            }
        }
    }

    func resolve(_ approved: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        request = nil
        continuation?.resume(returning: approved)
        continuation = nil
    }
}