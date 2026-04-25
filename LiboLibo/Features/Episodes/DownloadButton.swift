import SwiftUI

/// Кнопка скачать / удалить выпуск. Подхватывает статус из DownloadService.
struct DownloadButton: View {
    let episode: Episode
    /// Стиль рендера: компактная иконка для строки списка или плейера, либо
    /// большая bordered-кнопка для экрана выпуска.
    enum Style { case icon, button }
    var style: Style = .icon
    /// Цвет в неактивном состоянии. На белом фоне — primary, на тёмном плеере — white.
    var idleTint: Color = .primary

    @Environment(DownloadService.self) private var downloads

    var body: some View {
        let status = downloads.status(for: episode)

        Button {
            downloads.toggle(episode)
        } label: {
            switch style {
            case .icon: iconLabel(status)
            case .button: buttonLabel(status)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(for: status))
    }

    @ViewBuilder
    private func iconLabel(_ status: DownloadService.Status) -> some View {
        switch status {
        case .notDownloaded:
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(idleTint)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 28, minHeight: 28)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.liboRed)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func buttonLabel(_ status: DownloadService.Status) -> some View {
        switch status {
        case .notDownloaded:
            Label("Скачать", systemImage: "icloud.and.arrow.down")
                .frame(maxWidth: .infinity, minHeight: 44)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Загружается…")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        case .downloaded:
            Label("Скачано — удалить", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func accessibility(for status: DownloadService.Status) -> String {
        switch status {
        case .notDownloaded: return "Скачать выпуск"
        case .downloading:   return "Загружается"
        case .downloaded:    return "Удалить из загрузок"
        }
    }
}
