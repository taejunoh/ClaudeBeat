import SwiftUI

struct PopoverView: View {
    let usageState: UsageState
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: updated time + refresh
            TopBarView(
                lastUpdated: usageState.lastUpdated,
                onRefresh: onRefresh
            )

            Divider()

            if usageState.isError {
                errorSection
            } else if let response = usageState.response {
                usageSections(response)
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()

            // Bottom bar: settings + quit
            BottomBarView(onSettings: onSettings)
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func usageSections(_ response: UsageResponse) -> some View {
        UsageGaugeView(
            title: "Session (5h)",
            utilization: response.fiveHour.utilization,
            resetsAt: response.fiveHour.resetsAt,
            opusUtilization: response.sevenDayOpus?.utilization,
            sonnetUtilization: response.sevenDaySonnet?.utilization
        )

        Divider()

        WeeklyUsageView(
            allModels: response.sevenDay,
            sonnetOnly: response.sevenDaySonnet
        )

        if let extra = response.extraUsage, extra.isEnabled {
            Divider()
            ExtraUsageView(
                usedCredits: extra.usedCredits ?? 0,
                monthlyLimit: extra.monthlyLimit ?? 0
            )
        }
    }

    private var errorSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(usageState.errorMessage ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
