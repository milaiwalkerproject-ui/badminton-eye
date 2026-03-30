@preconcurrency import AVFoundation
import Accelerate
import Foundation

/// Computes temporal offset between two video files using audio cross-correlation.
/// Uses Accelerate/vDSP for hardware-accelerated computation.
struct AudioTemporalSync {

    /// Minimum cross-correlation confidence to consider the alignment valid.
    static let confidenceThreshold: Float = 0.3

    /// Target sample rate for downsampled audio (8kHz is sufficient for sync).
    static let targetSampleRate: Double = 8000

    /// Result of audio temporal alignment.
    struct SyncResult: Sendable {
        let offsetSeconds: Double   // Positive = video2 starts after video1
        let confidence: Float       // 0.0-1.0 normalized correlation peak
        let isReliable: Bool        // confidence >= threshold
    }

    /// Compute temporal offset between two video files using audio cross-correlation.
    /// - Returns: SyncResult with offset in seconds and confidence score.
    static func computeOffset(video1: URL, video2: URL) async throws -> SyncResult {
        let audio1 = try await extractAudioSamples(from: video1)
        let audio2 = try await extractAudioSamples(from: video2)

        guard !audio1.isEmpty, !audio2.isEmpty else {
            return SyncResult(offsetSeconds: 0, confidence: 0, isReliable: false)
        }

        // Cross-correlate using vDSP
        let (lagSamples, peakValue) = crossCorrelate(signal: audio1, filter: audio2)

        let offsetSeconds = Double(lagSamples) / targetSampleRate

        // Normalize confidence: peak relative to RMS energy
        let rms1 = rmsEnergy(audio1)
        let rms2 = rmsEnergy(audio2)
        let normFactor = rms1 * rms2 * Float(min(audio1.count, audio2.count))
        let confidence = normFactor > 0 ? min(peakValue / normFactor, 1.0) : 0

        return SyncResult(
            offsetSeconds: offsetSeconds,
            confidence: confidence,
            isReliable: confidence >= confidenceThreshold
        )
    }

    // MARK: - Audio Extraction

    /// Extract mono PCM float samples from a video's audio track, downsampled to targetSampleRate.
    private static func extractAudioSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }
        }

        return samples
    }

    // MARK: - Cross-Correlation via vDSP

    /// Compute cross-correlation and return (lag in samples, peak value).
    private static func crossCorrelate(signal: [Float], filter: [Float]) -> (Int, Float) {
        let signalCount = signal.count
        let filterCount = filter.count

        // Output length for valid correlation
        let resultCount = signalCount + filterCount - 1
        var result = [Float](repeating: 0, count: resultCount)

        // vDSP_conv: convolve signal with reversed filter = cross-correlation
        signal.withUnsafeBufferPointer { sigBuf in
            filter.withUnsafeBufferPointer { filtBuf in
                vDSP_conv(
                    sigBuf.baseAddress!, 1,
                    filtBuf.baseAddress! + filtBuf.count - 1, -1,
                    &result, 1,
                    vDSP_Length(resultCount),
                    vDSP_Length(filterCount)
                )
            }
        }

        // Find peak
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(result, 1, &maxVal, &maxIdx, vDSP_Length(resultCount))

        // Convert index to lag: center of correlation is at (filterCount - 1)
        let lagSamples = Int(maxIdx) - (filterCount - 1)

        return (lagSamples, maxVal)
    }

    // MARK: - Helpers

    private static func rmsEnergy(_ samples: [Float]) -> Float {
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return sqrtf(sumSquares / Float(samples.count))
    }
}
