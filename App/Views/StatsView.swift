import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var soulseek: SoulseekModel
    @State private var range = 14
    @State private var confirmReset = false

    var body: some View {
        // Read revision so the view refreshes when stats are saved.
        let _ = stats.revision
        let days = stats.lastDays(range)
        let totals = stats.totals
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("Listened", Formatting.hours(stats.totalSeconds), "headphones")
                    tile("Plays", "\(stats.totalPlays)", "play.circle")
                    tile("Downloaded", Formatting.bytes(totals.downloadedBytes), "arrow.down.circle")
                    tile("Uploaded", Formatting.bytes(totals.uploadedBytes), "arrow.up.circle")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Range", selection: $range) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                ListeningChart(days: days)
                    .frame(height: 170)
                CompatLabeledContent("This period", value: Formatting.hours(days.reduce(0) { $0 + $1.minutes * 60 }))
                CompatLabeledContent("Daily average", value: Formatting.hours(days.reduce(0) { $0 + $1.minutes * 60 } / Double(max(range, 1))))
            } header: {
                Text("Listening")
            }

            ranked("Top Songs", stats.topSongs(limit: 10), detail: true)
            ranked("Top Artists", stats.topArtists(limit: 10), detail: false)
            ranked("Top Albums", stats.topAlbums(limit: 10), detail: true)

            Section {
                CompatLabeledContent("Songs downloaded", value: "\(totals.downloadedFiles)")
                CompatLabeledContent("Songs uploaded", value: "\(totals.uploadedFiles)")
                CompatLabeledContent("People you've shared with", value: "\(totals.peers.count)")
                CompatLabeledContent("Share ratio", value: ratio(totals))
                CompatLabeledContent("Shared right now", value: "\(library.tracks.count) songs")
                CompatLabeledContent("Uploaded this session", value: Formatting.bytes(stats.sessionUploadedBytes))
                CompatLabeledContent("Counting since", value: totals.since.formatted(date: .abbreviated, time: .omitted))
            } header: {
                Text("Soulseek")
            }

            Section {
                Button("Reset Stats", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Stats stay on this iPhone. A play counts after 30 seconds (or half of a shorter song).")
            }
        }
        .navigationTitle("Stats")
        .confirmationDialog("Reset all stats?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { stats.reset() }
        }
    }

    private func ratio(_ totals: StatsStore.Totals) -> String {
        guard totals.downloadedBytes > 0 else { return totals.uploadedBytes > 0 ? "∞" : "–" }
        return String(format: "%.2f", Double(totals.uploadedBytes) / Double(totals.downloadedBytes))
    }

    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func ranked(_ title: String, _ items: [StatsStore.Ranked], detail: Bool) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1)
                            if detail, !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(item.plays) plays").font(.caption.monospacedDigit())
                            Text(Formatting.hours(item.seconds)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Compact numbers for the Settings row.
struct StatsPreview: View {
    @EnvironmentObject private var stats: StatsStore

    var body: some View {
        let _ = stats.revision
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stats")
                Text("\(Formatting.hours(stats.seconds(inLast: 7))) this week · ↑ \(Formatting.bytes(stats.totals.uploadedBytes)) shared")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Minutes listened per day: Swift Charts on iOS 16+, plain bars on iOS 15.
private struct ListeningChart: View {
    let days: [StatsStore.DayTotal]

    var body: some View {
        if #available(iOS 16, *) {
            Chart(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.minutes))
                    .foregroundStyle(.tint)
                    .cornerRadius(3)
            }
            .chartYAxisLabel("min")
        } else {
            SimpleBarChart(days: days)
        }
    }
}

/// iOS 15: bars drawn by hand in Swift Charts' default style — gridlines with the minute
/// scale on the trailing edge, dates along the bottom.
private struct SimpleBarChart: View {
    let days: [StatsStore.DayTotal]

    private var ticks: [Double] {
        let peak = days.map(\.minutes).max() ?? 0
        guard peak > 0 else { return [0, 1] }
        // A "nice" step (1, 2 or 5 × 10ⁿ) giving at most four gridlines above zero.
        let magnitude = pow(10, floor(log10(peak / 4)))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { peak / $0 <= 4 } ?? 10 * magnitude
        let top = ceil(peak / step) * step
        return stride(from: 0, through: top, by: step).map { $0 }
    }

    private var dateTicks: [StatsStore.DayTotal] {
        guard days.count > 1 else { return days }
        let stride = max(1, Int((Double(days.count) / 4).rounded(.up)))
        return days.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }

    var body: some View {
        let scale = ticks
        let top = scale.last ?? 1
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Text("min").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                GeometryReader { geometry in
                    let height = geometry.size.height
                    ZStack(alignment: .bottomLeading) {
                        ForEach(scale, id: \.self) { tick in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 0.5)
                                .offset(y: -height * CGFloat(tick / top))
                        }
                        HStack(alignment: .bottom, spacing: days.count > 20 ? 2 : 4) {
                            ForEach(days) { day in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(.tint)
                                    .frame(height: height * CGFloat(day.minutes / top))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                }
                GeometryReader { geometry in
                    ForEach(scale, id: \.self) { tick in
                        Text("\(Int(tick))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .position(x: 12, y: geometry.size.height * CGFloat(1 - tick / top))
                    }
                }
                .frame(width: 24)
            }
            HStack(spacing: 0) {
                ForEach(dateTicks) { day in
                    Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if day.id != dateTicks.last?.id { Spacer(minLength: 0) }
                }
                Spacer().frame(width: 30)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes listened per day")
    }
}
