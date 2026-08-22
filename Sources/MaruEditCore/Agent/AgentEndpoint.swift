import Foundation

/// Where the private socket lives, and how a bridge finds it.
///
/// ADR-011 assumed one endpoint per user. MaruEdit has no single-instance
/// lock — `main.swift` enters the event loop directly — so two running copies
/// would fight over one discovery file and could unlink each other's live
/// socket. Endpoints are therefore per instance, listed in a registry that
/// discovery reads, and reclaiming one takes more than an ownership check.
public enum AgentEndpoint {
    public static let directoryName = "ExternalControl"

    public struct Instance: Equatable, Sendable {
        public let serverInstanceID: String
        public let pid: Int32
        /// Distinguishes a live process from a new one that reused the pid.
        public let startTime: TimeInterval
        public let socketPath: String
        public let protocolMajor: Int

        public init(
            serverInstanceID: String, pid: Int32, startTime: TimeInterval,
            socketPath: String, protocolMajor: Int = AgentEnvelope.version
        ) {
            self.serverInstanceID = serverInstanceID
            self.pid = pid
            self.startTime = startTime
            self.socketPath = socketPath
            self.protocolMajor = protocolMajor
        }

        public var json: JSONValue {
            .object([
                "serverInstanceID": .string(serverInstanceID),
                "pid": .int(Int(pid)),
                "startTime": .double(startTime),
                "socketPath": .string(socketPath),
                "protocolMajor": .int(protocolMajor),
            ])
        }

        public static func parse(_ value: JSONValue) -> Instance? {
            guard let id = value["serverInstanceID"]?.stringValue,
                  let pid = value["pid"]?.intValue,
                  let socketPath = value["socketPath"]?.stringValue
            else { return nil }
            let startTime = value["startTime"].flatMap {
                if case .double(let d) = $0 { return d }
                if case .int(let i) = $0 { return Double(i) }
                return nil
            } ?? 0
            return Instance(
                serverInstanceID: id, pid: Int32(pid), startTime: startTime,
                socketPath: socketPath,
                protocolMajor: value["protocolMajor"]?.intValue ?? AgentEnvelope.version)
        }
    }

    public enum DiscoveryError: Error, Equatable {
        case notRunning
        /// Two or more instances are live. Guessing newest, first, or frontmost
        /// could expose the wrong documents, so discovery fails closed and the
        /// human names one.
        case ambiguous([String])
        case unknownInstance(String)
        case unreadableRegistry
    }

    // MARK: - Layout

    public static func supportDirectory(home: URL) -> URL {
        home
            .appendingPathComponent("Library/Application Support/MaruEdit", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func registryURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("instances.json")
    }

    public static func instanceDirectory(home: URL, serverInstanceID: String) -> URL {
        supportDirectory(home: home)
            .appendingPathComponent("instance-\(serverInstanceID)", isDirectory: true)
    }

    /// Discovery data only. The token deliberately does **not** live here:
    /// ADR-011 §3.1 forbids it, and it has its own `0600` file so a reader of
    /// the registry learns nothing that authorizes anything.
    public static func endpointURL(home: URL, serverInstanceID: String) -> URL {
        instanceDirectory(home: home, serverInstanceID: serverInstanceID)
            .appendingPathComponent("endpoint.json")
    }

    public static func tokenURL(home: URL, serverInstanceID: String) -> URL {
        instanceDirectory(home: home, serverInstanceID: serverInstanceID)
            .appendingPathComponent("token")
    }

    /// Sockets live in a deliberately short directory, separate from the
    /// instance directory that holds the endpoint file and token.
    ///
    /// `sockaddr_un.sun_path` is 104 bytes on Darwin, and the obvious layout —
    /// `…/ExternalControl/instance-<16 hex>/control.sock` — is 108 characters
    /// for a short home directory, so it fails to bind before anyone types a
    /// long username. Regular files have no such limit, so only the socket
    /// needs the short path.
    public static func socketDirectory(home: URL) -> URL {
        home
            .appendingPathComponent("Library/Application Support/MaruEdit", isDirectory: true)
            .appendingPathComponent("EC", isDirectory: true)
    }

    /// Short enough to be unique in practice while leaving room for a long home
    /// directory: the full instance id lives in the registry.
    public static func socketName(serverInstanceID: String) -> String {
        String(serverInstanceID.prefix(8)) + ".sock"
    }

    public static func socketURL(home: URL, serverInstanceID: String) -> URL {
        socketDirectory(home: home)
            .appendingPathComponent(socketName(serverInstanceID: serverInstanceID))
    }

    public static func credentialsURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("credentials.json")
    }

    // MARK: - Registry

    public static func readRegistry(home: URL) -> [Instance] {
        guard let data = try? Data(contentsOf: registryURL(home: home)),
              let value = try? JSONValue.decode(data),
              let entries = value["instances"]?.arrayValue
        else { return [] }
        return entries.compactMap(Instance.parse)
    }

    /// Registry writes take a lock file, so two instances starting together
    /// cannot lose each other's entry to a read-modify-write race.
    public static func updateRegistry(
        home: URL,
        _ transform: ([Instance]) -> [Instance]
    ) throws {
        let directory = supportDirectory(home: home)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let lockURL = directory.appendingPathComponent("instances.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw DiscoveryError.unreadableRegistry }
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }

        let updated = transform(readRegistry(home: home))
        let payload = JSONValue.object(["instances": .array(updated.map(\.json))])
        try payload.encoded().write(to: registryURL(home: home), options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: registryURL(home: home).path)
    }

    /// Whether a registry entry still describes a live MaruEdit.
    ///
    /// A pid alone is not enough — pids are reused — so the recorded start time
    /// must match too, and the socket must still exist.
    public static func isAlive(_ instance: Instance, now: (Int32) -> TimeInterval?) -> Bool {
        guard FileManager.default.fileExists(atPath: instance.socketPath) else { return false }
        guard let started = now(instance.pid) else { return false }
        return abs(started - instance.startTime) < 1.0
    }

    /// Picks the instance a bridge should talk to.
    ///
    /// Fails closed when more than one is live: a wrong guess here means an
    /// agent reads or edits documents in a window the human was not thinking
    /// about.
    public static func resolve(
        instances: [Instance],
        requestedID: String?
    ) -> Result<Instance, DiscoveryError> {
        if let requestedID {
            guard let match = instances.first(where: { $0.serverInstanceID == requestedID }) else {
                return .failure(.unknownInstance(requestedID))
            }
            return .success(match)
        }
        switch instances.count {
        case 0: return .failure(.notRunning)
        case 1: return .success(instances[0])
        default: return .failure(.ambiguous(instances.map(\.serverInstanceID)))
        }
    }

    // MARK: - Process start time

    /// Start time of a pid, from the kernel, used to tell a live process from a
    /// pid that has been reused.
    public static func processStartTime(pid: Int32) -> TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        guard started.tv_sec != 0 || started.tv_usec != 0 else { return nil }
        return TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000
    }
}
