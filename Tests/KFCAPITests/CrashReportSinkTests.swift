import Foundation
import Testing
@testable import KFCAPI

@Suite("CrashReportSink")
struct CrashReportSinkTests {

    @Test("CrashReport initializer sets all fields")
    func crashReportInit() {
        let report = CrashReport(
            reportID: "r1",
            name: "TestException",
            reason: "something broke",
            language: "Swift",
            stackTrace: ["frame1", "frame2"],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        #expect(report.reportID == "r1")
        #expect(report.name == "TestException")
        #expect(report.reason == "something broke")
        #expect(report.language == "Swift")
        #expect(report.stackTrace == ["frame1", "frame2"])
    }

    @Test("NoOpCrashReportSink does nothing")
    func noOpSink() {
        let sink = NoOpCrashReportSink()
        let report = CrashReport(reportID: "x", name: "y")
        sink.didCapture(report: report)
        // Should not crash
    }

    @Test("CrashReportSink receives report from simulated forwarding")
    func sinkReceivesReport() {
        final class MockSink: CrashReportSink, @unchecked Sendable {
            var reports: [CrashReport] = []
            func didCapture(report: CrashReport) { reports.append(report) }
        }

        var config = KFCrashConfig()
        let mock = MockSink()
        config.sink = mock

        // Simulate DefaultKFCrashService forwarding
        let report = CrashReport(
            reportID: UUID().uuidString,
            name: "RuntimeError",
            reason: "nil dereference",
            language: "Swift",
            stackTrace: Thread.callStackSymbols
        )
        config.sink?.didCapture(report: report)

        #expect(mock.reports.count == 1)
        #expect(mock.reports.first?.name == "RuntimeError")
        #expect(mock.reports.first?.reason == "nil dereference")
    }
}
