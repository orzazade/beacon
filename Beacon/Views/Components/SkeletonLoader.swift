import SwiftUI

// MARK: - Skeleton View

/// Base skeleton loading element with shimmer animation
/// Provides visual feedback during async loading operations
struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var shimmerOffset: CGFloat = -200

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.4),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 100)
                .offset(x: shimmerOffset)
            )
            .mask(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 200
                }
            }
    }
}

// MARK: - Skeleton Task Row

/// Skeleton placeholder mimicking UnifiedTaskRow layout
/// Shows source icon placeholder, title, and subtitle
struct SkeletonTaskRow: View {
    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        HStack(spacing: 12) {
            // Source icon placeholder (circle)
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                // Title placeholder (80% width)
                SkeletonView(height: 14, cornerRadius: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Subtitle placeholder (60% width)
                HStack {
                    SkeletonView(width: 60, height: 10, cornerRadius: 2)
                    Spacer()
                    // Priority badge placeholder
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Skeleton Task List

/// A list of skeleton task rows for loading state
/// Displays multiple placeholder rows during task fetching
struct SkeletonTaskList: View {
    let rowCount: Int

    init(rowCount: Int = 8) {
        self.rowCount = rowCount
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    SkeletonTaskRow()

                    if index < rowCount - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }
}

// MARK: - Skeleton Briefing Section

/// Skeleton placeholder mimicking BriefingSectionHeader + items layout
/// Shows section header skeleton and 3 item row skeletons
struct SkeletonBriefingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header skeleton
            HStack(spacing: 8) {
                // Icon placeholder
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 20, height: 20)

                // Title placeholder
                SkeletonView(width: 100, height: 14, cornerRadius: 3)

                // Count badge placeholder
                SkeletonView(width: 24, height: 16, cornerRadius: 8)

                Spacer()

                // Chevron placeholder
                SkeletonView(width: 10, height: 10, cornerRadius: 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Item rows skeleton (3 items)
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBriefingItemRow()
            }
        }
    }
}

// MARK: - Skeleton Briefing Item Row

/// Skeleton placeholder for a briefing item row
struct SkeletonBriefingItemRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Source indicator placeholder
            SkeletonView(width: 4, height: 32, cornerRadius: 2)

            VStack(alignment: .leading, spacing: 4) {
                // Title placeholder
                SkeletonView(height: 13, cornerRadius: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Subtitle placeholder
                SkeletonView(width: 150, height: 11, cornerRadius: 2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Skeleton Greeting

/// Skeleton placeholder for the briefing greeting
struct SkeletonGreeting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Greeting text placeholder
            SkeletonView(width: 200, height: 18, cornerRadius: 4)

            // Date text placeholder
            SkeletonView(width: 140, height: 14, cornerRadius: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Skeleton Briefing Content

/// Full skeleton layout for briefing content
/// Shows greeting, divider, and multiple section skeletons
struct SkeletonBriefingContent: View {
    let sectionCount: Int

    init(sectionCount: Int = 3) {
        self.sectionCount = sectionCount
    }

    var body: some View {
        VStack(spacing: 0) {
            // Skeleton greeting
            SkeletonGreeting()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    // Skeleton sections
                    ForEach(0..<sectionCount, id: \.self) { index in
                        SkeletonBriefingSection()

                        if index < sectionCount - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Skeleton View - Basic") {
    VStack(spacing: 16) {
        SkeletonView(width: 200, height: 14, cornerRadius: 4)
        SkeletonView(width: 150, height: 10, cornerRadius: 2)
        SkeletonView(height: 40, cornerRadius: 8)
    }
    .padding()
}

#Preview("Skeleton Task Row") {
    VStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { index in
            SkeletonTaskRow()
            if index < 4 {
                Divider()
                    .padding(.leading, 44)
            }
        }
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Skeleton Task List") {
    SkeletonTaskList(rowCount: 6)
        .frame(width: 320, height: 400)
}

#Preview("Skeleton Briefing Section") {
    VStack(spacing: 0) {
        SkeletonBriefingSection()
        Divider()
        SkeletonBriefingSection()
    }
    .frame(width: 360)
    .padding(.vertical)
}

#Preview("Skeleton Briefing Content") {
    SkeletonBriefingContent(sectionCount: 3)
        .frame(width: 360, height: 500)
}
