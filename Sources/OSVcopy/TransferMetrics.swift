import Foundation

/// 정리(복사·이동) 구간의 순간(EMA)·평균 전송 속도 및 ETA.
struct TransferMetrics: Sendable {
    private(set) var bytesCumulative: Int64 = 0
    private var organizeStart: Date?
    private var lastSampleTime: Date?
    private var lastSampleBytes: Int64 = 0
    private var emaBps: Double = 0
    private let emaAlpha: Double = 0.28

    mutating func beginOrganize(at now: Date = .now) {
        organizeStart = now
        lastSampleTime = now
        lastSampleBytes = 0
        bytesCumulative = 0
        emaBps = 0
    }

    mutating func recordFileCompleted(size: Int64, at now: Date = .now) {
        recordBytesDelta(size, at: now)
    }

    /// 복사·검사 중 청크 단위로 호출해 순간 속도(EMA)를 파일 경계 없이 갱신합니다.
    mutating func recordBytesDelta(_ delta: Int64, at now: Date = .now) {
        guard delta > 0 else { return }
        bytesCumulative += delta
        if let t0 = lastSampleTime {
            let dt = now.timeIntervalSince(t0)
            if dt > 0 {
                let sample = Double(delta) / dt
                if emaBps <= 0 {
                    emaBps = sample
                } else {
                    emaBps = emaAlpha * sample + (1 - emaAlpha) * emaBps
                }
            }
        }
        lastSampleTime = now
        lastSampleBytes = bytesCumulative
    }

    func averageBps(at now: Date = .now) -> Double {
        guard let t0 = organizeStart else { return 0 }
        let elapsed = now.timeIntervalSince(t0)
        guard elapsed > 0.05 else { return 0 }
        return Double(bytesCumulative) / elapsed
    }

    func instantaneousBps() -> Double {
        emaBps
    }

    /// 남은 바이트 / 평균 속도 (평균이 너무 작으면 nil).
    func estimatedRemainingSeconds(remainingBytes: Int64, at now: Date = .now) -> TimeInterval? {
        let avg = averageBps(at: now)
        guard avg > 1024, remainingBytes > 0 else { return nil }
        return Double(remainingBytes) / avg
    }
}
