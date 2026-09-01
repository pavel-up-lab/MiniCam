import Foundation

enum HikvisionPlaybackURL {
    static func starting(_ source: URL, at date: Date) -> URL? {
        guard var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let value = timestamp(date)
        var items = components.queryItems ?? []

        if let index = items.firstIndex(where: {
            $0.name.caseInsensitiveCompare("starttime") == .orderedSame
        }) {
            items[index].value = value
        } else {
            items.append(URLQueryItem(name: "starttime", value: value))
        }

        components.queryItems = items
        return components.url
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
