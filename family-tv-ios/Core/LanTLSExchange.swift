import Foundation
import Network
import Security
import CryptoKit

/// A request owns its connection. Certificate pins apply only to this paired TV,
/// never to URLSession, arbitrary hosts or the application's global trust policy.
final class LanTLSExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "familytv.local.exchange")
    private var continuation: CheckedContinuation<Data, Error>?
    private var connection: NWConnection?
    private var completed = false
    func request(endpoint: NWEndpoint, certificateSHA256: String, data: Data, timeout: TimeInterval = 4) async throws -> Data {
        guard data.count <= 32768, certificateSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw TVError.message(L10n.tr("局域网配对信息无效，请重新配对。")) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if self.completed { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    let tls = NWProtocolTLS.Options()
                    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
                    sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
                        let ref = sec_trust_copy_ref(trust).takeRetainedValue()
                        guard let certificates = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let leaf = certificates.first else { complete(false); return }
                        let hash = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
                        complete(hash == certificateSHA256)
                    }, self.queue)
                    let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
                    parameters.prohibitedInterfaceTypes = [.cellular]
                    let connection = NWConnection(to: endpoint, using: parameters); self.connection = connection
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            var length = UInt32(data.count).bigEndian
                            var frame = Data(bytes: &length, count: 4); frame.append(data)
                            connection.send(content: frame, completion: .contentProcessed { error in
                                if let error { self.finish(.failure(error)); return }
                                self.readExactly(4) { result in
                                    switch result {
                                    case let .failure(error): self.finish(.failure(error))
                                    case let .success(prefix):
                                        let count = prefix.reduce(0) { ($0 << 8) | Int($1) }
                                        guard (2...65536).contains(count) else { self.finish(.failure(TVError.message(L10n.tr("电视返回的数据无效。")))); return }
                                        self.readExactly(count) { self.finish($0) }
                                    }
                                }
                            })
                        case let .failed(error): self.finish(.failure(error))
                        case .cancelled: self.finish(.failure(CancellationError()))
                        default: break
                        }
                    }
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(TVError.message(L10n.tr("局域网连接超时，将尝试云端。")))) }
                }
            }
        } onCancel: { self.queue.async { self.finish(.failure(CancellationError())) } }
    }
    private func readExactly(_ length: Int, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        guard let connection else { completion(.failure(CancellationError())); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: length - accumulated.count) { data, _, done, error in
            if let error { completion(.failure(error)); return }
            var all = accumulated; if let data { all.append(data) }
            if all.count == length { completion(.success(all)) }
            else if done { completion(.failure(TVError.message(L10n.tr("电视连接提前结束。")))) }
            else { self.readExactly(length, accumulated: all, completion: completion) }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard !completed else { return }; completed = true
        let value = continuation; continuation = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        value?.resume(with: result)
    }
}
