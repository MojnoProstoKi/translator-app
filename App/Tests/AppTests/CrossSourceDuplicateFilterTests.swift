import Foundation
import TranslationEngine
import XCTest

@testable import RealtimeTranslator

@MainActor
final class CrossSourceDuplicateFilterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func event(_ id: UUID, _ source: AudioSourceType, _ text: String, final isFinal: Bool = false) -> TranslatedSegmentEvent {
        TranslatedSegmentEvent(segmentId: id, sourceType: source, originalText: text, translatedText: text, isFinal: isFinal, latency: 0)
    }

    /// The reported case: the mic's first partial is a single word, so the old one-shot check let
    /// it through and the line stayed duplicated.
    func testMicDuplicateIsCaughtOnLaterPartialAndRetracted() {
        let filter = CrossSourceDuplicateFilter()
        let sys = UUID(), mic = UUID()

        XCTAssertTrue(filter.process(event(mic, .microphone, "It"), now: t0).shows)
        XCTAssertEqual(
            filter.process(event(sys, .systemAudio, "It was a spontaneous"), now: t0.addingTimeInterval(0.3)),
            .init(shows: true, retractedSegmentIds: [mic])
        )
        XCTAssertFalse(filter.process(event(mic, .microphone, "It was a spontaneous discovery"), now: t0.addingTimeInterval(0.6)).shows)
        XCTAssertFalse(filter.process(event(mic, .microphone, "It was a spontaneous discovery, really.", final: true), now: t0.addingTimeInterval(1)).shows)
        XCTAssertTrue(filter.process(event(sys, .systemAudio, "It was a spontaneous discovery, really.", final: true), now: t0.addingTimeInterval(1.1)).shows)
    }

    func testMicArrivingAfterSystemAudioIsNeverShown() {
        let filter = CrossSourceDuplicateFilter()
        let sys = UUID(), mic = UUID()
        XCTAssertTrue(filter.process(event(sys, .systemAudio, "I came across"), now: t0).shows)
        XCTAssertEqual(filter.process(event(mic, .microphone, "I came"), now: t0.addingTimeInterval(0.2)), .init(shows: false))
        XCTAssertFalse(filter.process(event(mic, .microphone, "I came across a group...", final: true), now: t0.addingTimeInterval(1)).shows)
    }

    func testSystemAudioIsNeverSuppressed() {
        let filter = CrossSourceDuplicateFilter()
        XCTAssertTrue(filter.process(event(UUID(), .microphone, "Let's deploy it today", final: true), now: t0).shows)
        XCTAssertTrue(filter.process(event(UUID(), .systemAudio, "Let's deploy it today", final: true), now: t0.addingTimeInterval(0.5)).shows)
    }

    func testUserSpeechStartingWithSameWordIsShownAgain() {
        let filter = CrossSourceDuplicateFilter()
        let sys = UUID(), mic = UUID()
        _ = filter.process(event(sys, .systemAudio, "It was a spontaneous discovery"), now: t0)
        XCTAssertFalse(filter.process(event(mic, .microphone, "It"), now: t0.addingTimeInterval(0.5)).shows)
        XCTAssertTrue(filter.process(event(mic, .microphone, "It is my turn now"), now: t0.addingTimeInterval(1)).shows)
    }

    func testOldSystemSegmentOutsideWindowDoesNotSuppress() {
        let filter = CrossSourceDuplicateFilter()
        _ = filter.process(event(UUID(), .systemAudio, "Sounds good to me", final: true), now: t0)
        XCTAssertTrue(filter.process(event(UUID(), .microphone, "Sounds good to me", final: true), now: t0.addingTimeInterval(10)).shows)
    }
}
