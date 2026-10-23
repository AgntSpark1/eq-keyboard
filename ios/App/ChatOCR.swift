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

    struct Line {
        let text: String
        /// Vision 坐标：0...1，原点在左下角
        let box: CGRect
    }

    static func group(_ observations: [VNRecognizedTextObservation]) -> [ChatTurn] {
        group(observations.compactMap { obs in
            obs.topCandidates(1).first.map { Line(text: $0.string, box: obs.boundingBox) }
        })
    }

    /// 按从上到下排序后合并同一侧相邻的行
    static func group(_ lines: [Line]) -> [ChatTurn] {
        // 去掉状态栏和标题栏；截屏时键盘开着的话，键盘连同输入栏一起去掉
        let bottom = max(0.08, keyboardTop(lines).map { $0 + 0.12 } ?? 0)
        let bubbles = lines
            .filter { !$0.text.isEmpty && $0.box.minY > bottom && $0.box.maxY < 0.92 && !isCentered($0) }
            .sorted { $0.box.midY > $1.box.midY }
            .map { ChatTurn(speaker: $0.box.midX > 0.5 ? .me : .them, text: $0.text) }

        var turns: [ChatTurn] = []
        for line in bubbles {
            if var last = turns.last, last.speaker == line.speaker {
                last.text += " " + line.text
                turns[turns.count - 1] = last
            } else {
                turns.append(line)
            }
        }
        return turns
    }

    /// 时间、“以下为新消息”和标题栏的名字都居中，气泡则贴着左右两边
    static func isCentered(_ line: Line) -> Bool {
        line.box.width < 0.45 && abs(line.box.midX - 0.5) < 0.04
    }

    /// 键盘按键是一排很短的字：同一行并排 5 个以上，或被识别成一行“q w e r t y”
    static func keyboardTop(_ lines: [Line]) -> CGFloat? {
        func isShort(_ text: String) -> Bool { text.count <= 3 }
        let keys = lines.filter { isShort($0.text) && $0.box.width < 0.15 }
        var rows = lines.filter { line in
            let tokens = line.text.split(separator: " ")
            return tokens.count >= 5 && tokens.allSatisfy { isShort(String($0)) }
        }.map(\.box.maxY)
        for key in keys where keys.filter({ abs($0.box.midY - key.box.midY) < 0.015 }).count >= 5 {
            rows.append(key.box.maxY)
        }
        // 键盘在屏幕下半部分
        return rows.filter { $0 < 0.5 }.max()
    }
}
