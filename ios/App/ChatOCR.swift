import UIKit
import Vision

/// 在手机上识别聊天截图里的文字，并按气泡位置区分双方：靠右是自己，靠左是对方。
/// 截图本身不会上传。
enum ChatOCR {
    static func recognize(_ image: UIImage) async throws -> [ChatTurn] {
        guard let cgImage = image.cgImage else { return [] }
        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: request.results as? [VNRecognizedTextObservation] ?? [])
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return group(observations)
    }

    /// Vision 坐标原点在左下角，按从上到下排序后合并同一侧相邻的行
    static func group(_ observations: [VNRecognizedTextObservation]) -> [ChatTurn] {
        let lines = observations
            .filter { $0.boundingBox.minY > 0.08 && $0.boundingBox.maxY < 0.92 } // 去掉状态栏和输入栏
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { obs -> ChatTurn? in
                guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return ChatTurn(speaker: obs.boundingBox.midX > 0.5 ? .me : .them, text: text)
            }

        var turns: [ChatTurn] = []
        for line in lines {
            if var last = turns.last, last.speaker == line.speaker {
                last.text += " " + line.text
                turns[turns.count - 1] = last
            } else {
                turns.append(line)
            }
        }
        return turns
    }
}
