# FlutterAuto — Current Architecture

> **Status:** Architecture snapshot based on the current implementation and integration tests. This documents the known components and their responsibilities. It does **not** claim that Android Auto service discovery, channel establishment, or projection is complete.

## Scope

FlutterAuto is a Flutter/Dart Android Auto head-unit client. It connects to an Android phone through an ADB-forwarded TCP socket, initializes protocol messaging, negotiates the Android Auto protocol version, and then performs the TLS handshake. Development work is continuing toward a complete head-unit session.

## Component overview

```mermaid
flowchart TB
    UI["Flutter UI<br/>MainApp / device selection"]
    SESSION["HeadunitSession<br/>Session lifecycle and orchestration"]
    ADB["AdbManager<br/>ADB setup and port forwarding"]
    IDENTITY["HeadUnitIdentity<br/>Certificate and private key"]
    SOCKET["Dart Socket<br/>127.0.0.1:5277"]
    PC["ProtocolConnection<br/>Protocol framing and I/O"]
    ROUTER["MessageRouter<br/>Incoming message routing"]
    VH["VersionHandshake<br/>Protocol version negotiation"]
    TLS["AndroidAutoTlsClient<br/>TLS client and handshake"]
    TRANSPORT["SslHandshakeTransport<br/>TLS handshake byte transport"]
    PHONE["Android Auto phone"]

    UI --> SESSION
    SESSION --> ADB
    SESSION --> IDENTITY
    SESSION --> SOCKET
    SOCKET --> PC
    PC <--> ROUTER
    SESSION --> VH
    VH <--> ROUTER
    SESSION --> TLS
    TLS --> TRANSPORT
    TRANSPORT <--> PC
    PC <--> PHONE

    NEXT["Next milestones:<br/>Service discovery and channel setup"]
    SESSION -. future work .-> NEXT
```

The diagram shows conceptual class relationships. The exact behavior of the TLS transport depends on the implementations of `AndroidAutoTlsClient` and `SslHandshakeTransport`.

## Known responsibilities

| Component | Responsibility |
| --- | --- |
| `MainApp` / Flutter UI | Provides the application interface and device-selection workflow. |
| `AdbManager` | Initializes the ADB-based link and configures the port forwarding used by the app. |
| `HeadunitSession` | Orchestrates connection setup, version negotiation, TLS setup, session state transitions, and resource cleanup. |
| `HeadUnitIdentity` | Ensures the head-unit certificate and private key are available for TLS setup. |
| `ProtocolConnection` | Sends and receives protocol data over the TCP socket and provides protocol framing and I/O. |
| `MessageRouter` | Routes incoming protocol messages to the appropriate handler. |
| `VersionHandshake` | Exchanges version-negotiation messages through the message router and returns a `VersionHandshakeResult`. |
| `AndroidAutoTlsClient` | Coordinates the TLS client connection and handshake. |
| `SslHandshakeTransport` | Bridges TLS handshake data to and from the existing protocol connection. |

## Connection and handshake sequence

The order below follows the supplied `HeadunitSession.connect()` implementation.

```mermaid
sequenceDiagram
    autonumber
    participant Test as Integration test
    participant S as HeadunitSession
    participant A as AdbManager
    participant Phone as Android Auto phone
    participant PC as ProtocolConnection
    participant R as MessageRouter
    participant V as VersionHandshake
    participant I as HeadUnitIdentity
    participant T as AndroidAutoTlsClient
    participant X as SslHandshakeTransport

    Test->>S: connect()
    S->>S: State = connecting

    opt configureAdb = true
        S->>A: initializeAndroidAutoLink()
        A-->>S: ADB setup complete
    end

    S->>Phone: Connect via forwarded TCP socket
    Phone-->>S: TCP connection established

    S->>PC: Create ProtocolConnection(socket)
    S->>R: Create MessageRouter(protocolConnection)
    S->>S: State = negotiatingVersion

    Note over S,V: 1. Version negotiation occurs before TLS
    S->>V: run()
    V->>R: Send version request
    R->>PC: Send protocol message
    PC->>Phone: Version request bytes
    Phone-->>PC: Version response bytes
    PC-->>R: Incoming response
    R-->>V: Route version response
    V-->>S: VersionHandshakeResult

    S->>PC: Check connection is still open
    S->>I: ensureIdentity()
    I-->>S: Identity ready
    S->>I: debugCertificatePem()

    Note over S,X: 2. TLS handshake occurs after version negotiation
    S->>T: Create AndroidAutoTlsClient
    T->>X: Use SslHandshakeTransport
    S->>T: connect()
    T->>X: Exchange TLS handshake data
    X->>PC: Read/write through protocol connection
    PC->>Phone: TLS handshake bytes
    Phone-->>PC: TLS handshake bytes
    X-->>T: Handshake data
    T-->>S: TLS connection established

    S->>PC: Check connection is still open
    S->>S: State = connected
    S-->>Test: Return VersionHandshakeResult

    Note over S,Phone: Service discovery and channel setup are not established by this sequence
```

### Simplified state machine

```mermaid
stateDiagram-v2
    [*] --> disconnected

    disconnected --> connecting: connect()
    connecting --> negotiatingVersion: TCP connected and router initialized
    connecting --> failed: ADB or TCP setup fails

    negotiatingVersion --> tlsHandshake: Version negotiation succeeds
    negotiatingVersion --> failed: Version negotiation fails

    tlsHandshake --> connected: TLS succeeds and connection remains open
    tlsHandshake --> failed: TLS or connection check fails

    connected --> disconnected: TCP connection closes
    connected --> disconnecting: disconnect()
    connecting --> disconnecting: disconnect()
    negotiatingVersion --> disconnecting: disconnect()
    failed --> disconnecting: disconnect()

    disconnecting --> disconnected: Resources closed

    connected --> serviceDiscovery: Future milestone
    serviceDiscovery --> channelsReady: Services and channels established
    serviceDiscovery --> failed: Protocol error or timeout
```

> `tlsHandshake`, `serviceDiscovery`, and `channelsReady` in this diagram are conceptual labels. The current `HeadunitSessionState` enum contains `disconnected`, `connecting`, `negotiatingVersion`, `connected`, `disconnecting`, and `failed`. It does not currently contain a dedicated TLS or service-discovery state.

## Current verified progress

Development logs previously reported:

```text
[TLS] SSL_do_handshake result=1, error=0
[TLS] Handshake completed successfully.
Version negotiation succeeded: Instance of 'VersionHandshakeResult'
```

This indicates that TLS completed successfully and version negotiation returned successfully in the reported run. The supplied `HeadunitSession.connect()` code confirms that version negotiation runs before TLS.

The integration tests include:

- A version-negotiation test that checks `result.majorVersion > 0` and `result.status.value == 0`.
- A head-unit session test that calls `session.connect()` and checks `session.isConnected`.

These checks do not independently prove that service discovery, channel establishment, media, navigation, or projection works.

## Suggested next architecture milestones

1. **Control-message handling:** Handle protocol control messages after version negotiation and TLS setup as required by the reference implementation.
2. **Service discovery:** Implement service-discovery requests, responses, and payload parsing.
3. **Channel lifecycle:** Implement channel creation, opening, closing, and lifecycle management.
4. **Service-specific handlers:** Add payload parsing and dispatch for individual Android Auto services.
5. **Session robustness:** Improve timeout handling, connection-loss recovery, reconnect behavior, and state transitions.
6. **Integration testing:** Test each protocol transition against a real device and compare framing, message types, identifiers, and payloads with the C++ reference.

Keep the implementation aligned with the reference protocol and verify each milestone independently before documenting it as complete.

## Failure boundaries to test

| Stage | Useful failure tests |
| --- | --- |
| ADB setup | ADB missing, device unauthorized, forwarding command failure |
| TCP connection | Port not forwarded, connection refused, connection timeout |
| Version negotiation | Unexpected message, nonzero status, unsupported version, timeout |
| Identity preparation | Missing certificate, missing private key, invalid identity |
| TLS handshake | Peer closes connection, malformed TLS data, handshake timeout |
| Session cleanup | Disconnect during setup, repeated disconnect, disposal after failure |
| Future service discovery | Unknown service, malformed payload, channel-open rejection, phone disconnect |

## Operational notes

- Keep protocol packet and byte dumps at `fine` log level.
- Include the current stage, error details, and stack trace in failure logs.
- Close the TLS client, message router, protocol connection, and underlying socket according to their ownership rules.
- Ensure the state exposed by `isConnected` accurately reflects the intended meaning of a connected session.
- Treat the certificate/private-key pair copied from the public C++ reference as development-only. Do not bundle that identity in a production APK: Flutter assets can be extracted from the built application.
