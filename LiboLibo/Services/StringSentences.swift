import Foundation

/// Хелперы для превью описания выпуска в строке списка. Раньше жили в
/// `RSSParser.swift`; после переезда на API парсер удалён, а нарезка
/// предложений по-прежнему нужна для EpisodeListItem.
extension String {
    /// Удаляет URL-ы (http/https/www.) и схлопывает оставшиеся пробелы.
    /// URL не должны попадать в превью — точки в URL ломают разбиение на предложения.
    var withoutURLs: String {
        var s = self
        s = s.replacingOccurrences(
            of: #"\bhttps?://[^\s,;<>«»"']+"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\bwww\.[^\s,;<>«»"']+"#,
            with: "",
            options: .regularExpression
        )
        // Чистим хвостовые «:» / «—» / повторные пробелы, оставшиеся от вырезанного URL.
        s = s.replacingOccurrences(of: #"[:\-–—]\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Возвращает первое предложение строки. Если в нём меньше 2 слов — берём первые два.
    /// Перед извлечением URL-ы вырезаются.
    func firstSentences(maxCount: Int = 2) -> String {
        let cleaned = self.withoutURLs
        guard !cleaned.isEmpty else { return "" }

        var sentences: [String] = []
        var buffer = ""
        for char in cleaned {
            buffer.append(char)
            if ".!?".contains(char) {
                let s = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                // Игнорируем «предложения» из 1–2 символов («.», «А.»), это аббревиатуры или мусор.
                if s.count > 2 { sentences.append(s) }
                buffer = ""
                if sentences.count >= maxCount { break }
            }
        }
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty && sentences.count < maxCount {
            sentences.append(leftover)
        }
        if sentences.isEmpty { return cleaned }

        // Если первое предложение короче 2 слов — добавляем второе (правило Ильи).
        let first = sentences[0]
        let firstWords = first.split { $0.isWhitespace }.count
        if firstWords < 2, sentences.count >= 2 {
            return sentences.prefix(2).joined(separator: " ")
        }
        return first
    }
}
