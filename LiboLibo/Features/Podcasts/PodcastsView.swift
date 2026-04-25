import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastsRepository.self) private var repository

    var body: some View {
        NavigationStack {
            List(repository.podcasts) { podcast in
                NavigationLink(value: podcast) {
                    PodcastRow(podcast: podcast)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Подкасты")
            .navigationDestination(for: Podcast.self) { podcast in
                PodcastDetailView(podcast: podcast)
            }
        }
    }
}

private struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AsyncImage(url: podcast.artworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(podcast.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PodcastsView()
        .environment(PodcastsRepository())
}
