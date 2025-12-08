//
//  OSCServer.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation
import Network

/// Represents a parsed OSC message
struct OSCMessage {
    let address: String
    let arguments: [Any]
}

/// OSC Server that listens for messages from M4L devices
@Observable
class OSCServer {
    static let shared = OSCServer()

    private var listener: NWListener?
    private let port: UInt16 = 47200
    private let queue = DispatchQueue(label: "com.byjoba.sordello.osc")

    var isRunning = false
    var lastMessage: String = ""

    init() {}

    func start() {
        do {
            let params = NWParameters.udp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("OSC Server listening on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.isRunning = false
                        print("OSC Server failed: \(error)")
                    case .cancelled:
                        self?.isRunning = false
                        print("OSC Server cancelled")
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("Failed to create OSC listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let message = self?.parseOSC(data: data) {
                    DispatchQueue.main.async {
                        self?.lastMessage = "\(message.address) \(message.arguments)"
                        self?.handleMessage(message)
                    }
                }
            }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            // Continue receiving
            if !isComplete {
                self?.receiveMessage(on: connection)
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: OSCMessage) {
        print("Received OSC: \(message.address) with \(message.arguments.count) arguments")

        switch message.address {
        case "/byJoBa/sordello/register":
            handleRegister(message)

        case "/byJoBa/sordello/unregister":
            handleUnregister(message)

        case "/byJoBa/sordello/extract":
            handleExtract(message)

        case "/byJoBa/sordello/open":
            handleOpen(message)

        case "/byJoBa/sordello/import":
            handleImport(message)

        case "/byJoBa/sordello/status":
            handleStatus(message)

        default:
            print("Unknown OSC address: \(message.address)")
        }
    }

    private func handleRegister(_ message: OSCMessage) {
        guard message.arguments.count >= 3,
              let instanceId = message.arguments[0] as? String,
              let projectPath = message.arguments[1] as? String,
              let liveVersion = message.arguments[2] as? String else {
            print("Invalid register message")
            return
        }

        print("Registering device \(instanceId) for project: \(projectPath)")

        let device = ConnectedDevice(
            id: instanceId,
            projectPath: projectPath,
            liveVersion: liveVersion,
            connectedAt: Date()
        )
        AppState.shared.registerDevice(device)

        // Parse the project file immediately
        parseAndUpdateProject(alsPath: projectPath, liveVersion: liveVersion)

        // Start watching for file changes
        FileWatcher.shared.watchFile(at: projectPath) { [weak self] in
            print("File changed: \(projectPath)")
            self?.parseAndUpdateProject(alsPath: projectPath, liveVersion: liveVersion)
        }
    }

    private func parseAndUpdateProject(alsPath: String, liveVersion: String) {
        let parser = AlsParser()
        guard parser.loadFile(at: URL(fileURLWithPath: alsPath)) else {
            print("Failed to parse project: \(parser.errorMessage ?? "unknown error")")
            return
        }

        let tracks = parser.getTracks()
        print("Parsed \(tracks.count) tracks from project")

        // Extract folder path from .als path
        let alsUrl = URL(fileURLWithPath: alsPath)
        let folderPath = alsUrl.deletingLastPathComponent().path

        // Get or create the project folder
        let project = AppState.shared.getOrCreateProject(folderPath: folderPath)

        // Find or create the LiveSet for this .als file
        let fileName = alsUrl.lastPathComponent
        let category: LiveSetCategory = fileName.hasPrefix(".subproject-") ? .subproject : .main

        var liveSet = project.liveSets.first(where: { $0.path == alsPath })
        if liveSet == nil {
            liveSet = LiveSet(path: alsPath, category: category)
            project.liveSets.append(liveSet!)
        }

        // Update the LiveSet
        liveSet!.liveVersion = liveVersion
        liveSet!.tracks = tracks
        liveSet!.buildHierarchy()
        liveSet!.lastUpdated = Date()

        project.lastUpdated = Date()
    }

    private func handleUnregister(_ message: OSCMessage) {
        guard let instanceId = message.arguments.first as? String else {
            print("Invalid unregister message")
            return
        }

        print("Unregistering device: \(instanceId)")
        AppState.shared.unregisterDevice(instanceId: instanceId)
    }

    private func handleExtract(_ message: OSCMessage) {
        guard message.arguments.count >= 3,
              let instanceId = message.arguments[0] as? String,
              let groupTrackId = message.arguments[1] as? Int32,
              let groupName = message.arguments[2] as? String else {
            print("Invalid extract message")
            return
        }

        print("Extract request from \(instanceId): group \(groupTrackId) (\(groupName))")
        // TODO: Implement extraction
    }

    private func handleOpen(_ message: OSCMessage) {
        guard let instanceId = message.arguments.first as? String else {
            print("Invalid open message")
            return
        }

        print("Open subproject request from: \(instanceId)")
        // TODO: Implement open
    }

    private func handleImport(_ message: OSCMessage) {
        guard let instanceId = message.arguments.first as? String else {
            print("Invalid import message")
            return
        }

        print("Import bounce request from: \(instanceId)")
        // TODO: Implement import
    }

    private func handleStatus(_ message: OSCMessage) {
        guard let instanceId = message.arguments.first as? String else {
            print("Invalid status message")
            return
        }

        print("Status request from: \(instanceId)")
        // TODO: Send status response
    }

    // MARK: - OSC Parsing

    private func parseOSC(data: Data) -> OSCMessage? {
        var offset = 0

        // Parse address
        guard let address = readOSCString(from: data, offset: &offset) else {
            print("Failed to parse OSC address")
            return nil
        }

        // Parse type tag
        guard let typeTag = readOSCString(from: data, offset: &offset) else {
            print("Failed to parse OSC type tag")
            return nil
        }

        // Type tag should start with ','
        guard typeTag.hasPrefix(",") else {
            print("Invalid type tag: \(typeTag)")
            return nil
        }

        // Parse arguments based on type tag
        var arguments: [Any] = []
        let types = String(typeTag.dropFirst()) // Remove leading ','

        for type in types {
            switch type {
            case "s": // String
                if let str = readOSCString(from: data, offset: &offset) {
                    arguments.append(str)
                }
            case "i": // Int32
                if let int = readOSCInt32(from: data, offset: &offset) {
                    arguments.append(int)
                }
            case "f": // Float32
                if let float = readOSCFloat32(from: data, offset: &offset) {
                    arguments.append(float)
                }
            default:
                print("Unknown OSC type: \(type)")
            }
        }

        return OSCMessage(address: address, arguments: arguments)
    }

    private func readOSCString(from data: Data, offset: inout Int) -> String? {
        var end = offset
        while end < data.count && data[end] != 0 {
            end += 1
        }

        guard end > offset else { return nil }

        let stringData = data[offset..<end]
        let string = String(data: stringData, encoding: .utf8)

        // OSC strings are null-terminated and padded to 4-byte boundary
        let length = end - offset + 1 // +1 for null terminator
        let paddedLength = (length + 3) & ~3 // Round up to 4 bytes
        offset += paddedLength

        return string
    }

    private func readOSCInt32(from data: Data, offset: inout Int) -> Int32? {
        guard offset + 4 <= data.count else { return nil }

        let value = data[offset..<offset+4].withUnsafeBytes { ptr in
            Int32(bigEndian: ptr.load(as: Int32.self))
        }
        offset += 4
        return value
    }

    private func readOSCFloat32(from data: Data, offset: inout Int) -> Float? {
        guard offset + 4 <= data.count else { return nil }

        let bits = data[offset..<offset+4].withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.load(as: UInt32.self))
        }
        offset += 4
        return Float(bitPattern: bits)
    }
}
