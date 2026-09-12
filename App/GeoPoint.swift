import Foundation

// MARK: - GeoPoint

/// Plain value type so MonitorModel never imports MapKit
/// (CLLocationCoordinate2D is not Equatable/Codable)
struct GeoPoint: Equatable, Hashable, Codable {
    let lat: Double
    let lon: Double
}

// MARK: - GeoSource

/// Where a station's coordinates came from, for pin confidence on the map
enum GeoSource: String, Codable {
    case qrz // exact lat/lon from the operator's QRZ record
    case grid // Maidenhead grid square center
    case dxcc // country centroid only
}

// MARK: - Maidenhead

enum Maidenhead {
    // MARK: Internal

    /// Center of a 4- or 6-character grid square (e.g. "FN31" / "FN31pr")
    static func center(_ grid: String) -> GeoPoint? {
        let chars = Array(grid.uppercased())
        guard chars.count >= 4,
              let fieldLon = value(chars[0], base: "A", limit: 18),
              let fieldLat = value(chars[1], base: "A", limit: 18),
              let squareLon = value(chars[2], base: "0", limit: 10),
              let squareLat = value(chars[3], base: "0", limit: 10)
        else {
            return nil
        }

        var lon = Double(fieldLon) * 20 - 180 + Double(squareLon) * 2
        var lat = Double(fieldLat) * 10 - 90 + Double(squareLat) * 1

        if chars.count >= 6,
           let subLon = value(chars[4], base: "A", limit: 24),
           let subLat = value(chars[5], base: "A", limit: 24)
        {
            lon += Double(subLon) * 2 / 24 + 1.0 / 24
            lat += Double(subLat) * 1 / 24 + 0.5 / 24
        } else {
            lon += 1
            lat += 0.5
        }
        return GeoPoint(lat: lat, lon: lon)
    }

    // MARK: Private

    private static func value(_ char: Character, base: Character, limit: Int) -> Int? {
        guard let scalar = char.unicodeScalars.first?.value,
              let baseScalar = base.unicodeScalars.first?.value
        else {
            return nil
        }
        let offset = Int(scalar) - Int(baseScalar)
        guard offset >= 0, offset < limit else {
            return nil
        }
        return offset
    }
}
