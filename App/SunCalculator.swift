// MARK: - Solar Calculator
// Pure-Swift NOAA simplified solar algorithm for sunrise/sunset computation.
// No external dependencies — uses only Foundation.
import Foundation

/// Computes local sunrise and sunset times using the NOAA simplified solar algorithm.
enum SunCalculator {

    /// Returns the local sunrise time for the given date and coordinates, or nil during polar day/night.
    static func sunriseTime(on date: Date, latitude: Double, longitude: Double) -> Date? {
        solarEvent(on: date, latitude: latitude, longitude: longitude, isSunrise: true)
    }

    /// Returns the local sunset time for the given date and coordinates, or nil during polar day/night.
    static func sunsetTime(on date: Date, latitude: Double, longitude: Double) -> Date? {
        solarEvent(on: date, latitude: latitude, longitude: longitude, isSunrise: false)
    }

    // MARK: - Core Algorithm

    private static func solarEvent(
        on date: Date,
        latitude: Double,
        longitude: Double,
        isSunrise: Bool
    ) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }

        // Julian Day Number (at noon UTC of the given calendar date)
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let jdn = Double(day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045)
        // Julian Day at midnight UTC
        let jd = jdn - 0.5

        // Julian Century
        let t = (jd - 2451545.0) / 36525.0

        // Geometric mean longitude of the sun (degrees)
        let l0 = fmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)

        // Geometric mean anomaly of the sun (degrees)
        let mDeg = 357.52911 + t * (35999.05029 - t * 0.0001537)
        let mRad = mDeg * .pi / 180.0

        // Sun's equation of center
        let c = sin(mRad) * (1.914602 - t * (0.004817 + t * 0.000014))
              + sin(2 * mRad) * (0.019993 - t * 0.000101)
              + sin(3 * mRad) * 0.000289

        // Sun's true longitude
        let sunLon = l0 + c

        // Sun's apparent longitude
        let omega = 125.04 - 1934.136 * t
        let lambdaDeg = sunLon - 0.00569 - 0.00478 * sin(omega * .pi / 180.0)
        let lambdaRad = lambdaDeg * .pi / 180.0

        // Mean obliquity of the ecliptic
        let epsilon0 = 23.0 + (26.0 + (21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0

        // Corrected obliquity
        let epsilonRad = (epsilon0 + 0.00256 * cos(omega * .pi / 180.0)) * .pi / 180.0

        // Sun declination
        let decRad = asin(sin(epsilonRad) * sin(lambdaRad))

        // Equation of time (minutes)
        let l0Rad = l0 * .pi / 180.0
        let eccent = 0.016708634 - t * (0.000042037 + t * 0.0000001267)
        let yy = tan(epsilonRad / 2) * tan(epsilonRad / 2)
        let etime = 4.0 * (180.0 / .pi) * (
              yy * sin(2 * l0Rad)
            - 2 * eccent * sin(mRad)
            + 4 * eccent * yy * sin(mRad) * cos(2 * l0Rad)
            - 0.5 * yy * yy * sin(4 * l0Rad)
            - 1.25 * eccent * eccent * sin(2 * mRad)
        )

        // Solar hour angle at sunrise/sunset (degrees from solar noon)
        // 90.833° accounts for atmospheric refraction and solar disk radius
        let latRad = latitude * .pi / 180.0
        let cosHA = cos(90.833 * .pi / 180.0) / (cos(latRad) * cos(decRad)) - tan(latRad) * tan(decRad)

        // Polar day or polar night — no sunrise or sunset
        guard cosHA >= -1.0 && cosHA <= 1.0 else { return nil }

        let haDeg = acos(cosHA) * 180.0 / .pi

        // Solar noon in UTC minutes from midnight
        let solarNoonMinutes = 720.0 - 4.0 * longitude - etime

        // Sunrise or sunset in UTC minutes from midnight
        let eventMinutes = isSunrise
            ? solarNoonMinutes - haDeg * 4.0
            : solarNoonMinutes + haDeg * 4.0

        // Build the result Date: start of the UTC calendar day + eventMinutes
        guard let utcMidnight = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)) else { return nil }
        let eventDate = utcMidnight.addingTimeInterval(eventMinutes * 60.0)
        return eventDate
    }
}
