import SwiftUI

/// Иконка-toggle подписки. Логика как у `DownloadButton`: подписан —
/// заполненная галочка в брендовом цвете, не подписан — контурный плюс
/// в `.secondary`.
struct SubscribeButton: View {
    let podcast: Podcast
    @Environment(SubscriptionsService.self) private var subscriptions

    var body: some View {
        Button {
            subscriptions.toggle(podcast)
        } label: {
            Image(systemName: subscriptions.isSubscribed(podcast)
                  ? "checkmark.circle.fill"
                  : "plus.circle")
                .font(.title3)
                .foregroundStyle(subscriptions.isSubscribed(podcast) ? Color.liboRed : .secondary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subscriptions.isSubscribed(podcast) ? "Отписаться" : "Подписаться")
    }
}
