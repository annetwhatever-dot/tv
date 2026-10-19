import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct SonosState: Equatable {
    let volume: Int
    let muted: Bool
}

@MainActor
protocol SonosCommunicating: AnyObject {
    func identify(host: String) async throws -> String
    func state(host: String) async throws -> SonosState
    func setVolume(_ volume: Int, host: String) async throws
    func setMuted(_ muted: Bool, host: String) async throws
}

final class XMLValues: NSObject, XMLParserDelegate {
    private var text = ""
    private(set) var values: [String: String] = [:]

    static func parse(_ data: Data) throws -> [String: String] {
        let delegate = XMLValues()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw ControlError.invalidResponse }
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { text = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName.components(separatedBy: ":").last!] = value }
        text = ""
    }
}

@MainActor
final class SonosClient: SonosCommunicating {
    private let service = "urn:schemas-upnp-org:service:RenderingControl:1"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        session = URLSession(configuration: configuration)
    }

    func identify(host: String) async throws -> String {
        let host = try LocalAddress.validated(host)
        let (data, response) = try await session.data(from: URL(string: "http://\(host):1400/xml/device_description.xml")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ControlError.invalidResponse }
        let fields = try XMLValues.parse(data)
        guard fields["manufacturer"]?.lowercased().contains("sonos") == true,
              let model = fields["modelName"] else { throw ControlError.device("That address does not belong to a Sonos speaker.") }
        return model
    }

    private func call(_ action: String, host: String, fields: String = "") async throws -> [String: String] {
        let host = try LocalAddress.validated(host)
        var request = URLRequest(url: URL(string: "http://\(host):1400/MediaRenderer/RenderingControl/Control")!)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="\(service)"><InstanceID>0</InstanceID><Channel>Master</Channel>\(fields)</u:\(action)></s:Body></s:Envelope>
        """.utf8)
        let (data, response) = try await session.data(for: request)
        let values = try XMLValues.parse(data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ControlError.device(values["errorDescription"] ?? "Sonos could not apply that setting.")
        }
        return values
    }

    func state(host: String) async throws -> SonosState {
        let volume = try await call("GetVolume", host: host)
        let mute = try await call("GetMute", host: host)
        let level = try LocalAddress.level(volume["CurrentVolume"])
        guard let currentMute = mute["CurrentMute"], ["0", "1"].contains(currentMute) else { throw ControlError.invalidResponse }
        return SonosState(volume: level, muted: currentMute == "1")
    }

    func setVolume(_ volume: Int, host: String) async throws {
        guard (0...100).contains(volume) else { throw ControlError.invalidResponse }
        _ = try await call("SetVolume", host: host, fields: "<DesiredVolume>\(volume)</DesiredVolume>")
    }

    func setMuted(_ muted: Bool, host: String) async throws {
        _ = try await call("SetMute", host: host, fields: "<DesiredMute>\(muted ? 1 : 0)</DesiredMute>")
    }
}
