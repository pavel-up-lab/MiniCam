import SwiftUI

struct ArchiveCalendarPopover: View {
    let segments: [RecordingSegment]
    let initialDate: Date
    let onCommit: (Date) -> Void

    @State private var displayedMonth: Date
    @State private var selectedDay: Date
    @State private var selectedHour: Int
    @State private var selectedMinute: Int

    private let calendar = Calendar.autoupdatingCurrent
    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )
    private let hourColumns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 8
    )

    init(
        segments: [RecordingSegment],
        initialDate: Date,
        onCommit: @escaping (Date) -> Void
    ) {
        self.segments = segments
        self.initialDate = initialDate
        self.onCommit = onCommit

        let calendar = Calendar.autoupdatingCurrent
        let month = calendar.dateInterval(of: .month, for: initialDate)?.start
            ?? initialDate
        _displayedMonth = State(initialValue: month)
        _selectedDay = State(initialValue: initialDate)
        _selectedHour = State(
            initialValue: calendar.component(.hour, from: initialDate)
        )
        _selectedMinute = State(
            initialValue: calendar.component(.minute, from: initialDate)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПЕРЕЙТИ В АРХИВ")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            monthHeader
            weekdayHeader
            dayGrid

            Divider()
                .overlay(Color.white.opacity(0.12))

            Text("ЧАС")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))

            hourGrid
            timeRow
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(red: 0.055, green: 0.065, blue: 0.071))
        .onAppear(perform: normalizeSelection)
        .onChange(of: segments) { _ in
            normalizeSelection()
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: -1))
            .accessibilityLabel("Предыдущий месяц")

            Spacer()

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: 1))
            .accessibilityLabel("Следующий месяц")
        }
        .foregroundStyle(accent)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayButton(day)
                } else {
                    Color.clear
                        .frame(height: 32)
                }
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let isAvailable = availability.isDayAvailable(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)

        return Button {
            selectedDay = day
            chooseNearestAvailableHour()
        } label: {
            Text(String(calendar.component(.day, from: day)))
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .background(
                    isSelected ? accent : Color.white.opacity(isAvailable ? 0.08 : 0.025),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.34)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hourGrid: some View {
        LazyVGrid(columns: hourColumns, spacing: 4) {
            ForEach(0..<24, id: \.self) { hour in
                let isAvailable = availableHours.contains(hour)
                let isSelected = selectedHour == hour

                Button {
                    selectedHour = hour
                } label: {
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .background(
                            isSelected ? accent : Color.white.opacity(isAvailable ? 0.08 : 0.025),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .opacity(isAvailable ? 1 : 0.32)
                .accessibilityLabel("\(hour) часов")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d:", selectedHour))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Picker("Минуты", selection: $selectedMinute) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 72)
            .accessibilityLabel("Минуты")

            Spacer()

            Button("Перейти") {
                if let commitDate {
                    onCommit(commitDate)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.62, green: 0.82, blue: 0.12))
            .disabled(commitDate == nil)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var availability: ArchiveCalendarAvailability {
        ArchiveCalendarAvailability(segments: segments, calendar: calendar)
    }

    private var availableHours: Set<Int> {
        availability.availableHours(on: selectedDay)
    }

    private var commitDate: Date? {
        guard let requested = calendar.date(
            bySettingHour: selectedHour,
            minute: selectedMinute,
            second: 0,
            of: selectedDay
        ) else {
            return nil
        }
        return availability.nearestPlayableDate(to: requested)
    }

    private var monthDays: [Date?] {
        guard
            let month = calendar.dateInterval(of: .month, for: displayedMonth),
            let days = calendar.range(of: .day, in: .month, for: displayedMonth)
        else {
            return []
        }

        let weekday = calendar.component(.weekday, from: month.start)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var values = Array<Date?>(repeating: nil, count: leadingCount)
        values.append(contentsOf: days.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: month.start)
        })
        return values
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var archiveMonthRange: ClosedRange<Date>? {
        guard
            let first = segments.min(by: { $0.start < $1.start }),
            let last = segments.max(by: { $0.end < $1.end }),
            let firstMonth = calendar.dateInterval(of: .month, for: first.start)?.start,
            let lastMonth = calendar.dateInterval(
                of: .month,
                for: last.end.addingTimeInterval(-0.001)
            )?.start
        else {
            return nil
        }
        return firstMonth...lastMonth
    }

    private func canMoveMonth(by offset: Int) -> Bool {
        guard
            let candidate = calendar.date(
                byAdding: .month,
                value: offset,
                to: displayedMonth
            ),
            let range = archiveMonthRange
        else {
            return false
        }
        return range.contains(candidate)
    }

    private func moveMonth(by offset: Int) {
        guard
            canMoveMonth(by: offset),
            let month = calendar.date(
                byAdding: .month,
                value: offset,
                to: displayedMonth
            )
        else {
            return
        }
        displayedMonth = month
    }

    private func normalizeSelection() {
        guard !segments.isEmpty else { return }

        if !availability.isDayAvailable(selectedDay) {
            let nearest = segments
                .flatMap { [$0.start, $0.end.addingTimeInterval(-0.001)] }
                .min(by: {
                    abs($0.timeIntervalSince(selectedDay))
                        < abs($1.timeIntervalSince(selectedDay))
                })
            if let nearest {
                selectedDay = nearest
                displayedMonth = calendar.dateInterval(
                    of: .month,
                    for: nearest
                )?.start ?? nearest
            }
        }

        chooseNearestAvailableHour()
    }

    private func chooseNearestAvailableHour() {
        guard let nearest = availableHours.min(by: {
            abs($0 - selectedHour) < abs($1 - selectedHour)
        }) else {
            return
        }
        selectedHour = nearest
    }
}
