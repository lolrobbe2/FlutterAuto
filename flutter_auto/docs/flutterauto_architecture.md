# FlutterAuto --- Current Architecture

> Status: architecture snapshot based on the implementation and test
> code currently available. This documents the known components and
> their responsibilities; it does **not** claim that Android Auto
> service discovery or projection is complete.

## Scope

FlutterAuto is a Flutter/Dart Android Auto head-unit client. It connects
to an Android phone through an ADB-forwarded TCP socket, establishes
TLS, negotiates the protocol version, and is being extended toward a
complete head-unit session.

## Component overview

``` mermaid
flowchart TB
    UI["Flutter UI<br/>MainApp / device selection"]
    ADB["AdbManager<br/>ADB setup, device commands,<br/>port forwarding"]
    SESSION["HeadunitSession<br/>session lifecycle / orchestration"]
    IDENTITY["HeadUnitIdentity<br/>head-unit certificate and key assets"]
    TLS["AndroidAutoTlsClient<br/>TLS client / handshake"]
    TRANSPORT["SslHandshakeTransport<br/>bridges TLS bytes to transport"]
    SOCKET["TCP Socket<br/>127.0.0.1:5277"]
    CONN["ProtocolConnection<br/>protocol framing and I/O"]
    ROUTER["MessageRouter<br/>routes protocol messages"]
    VERSION["VersionHandshake<br/>version negotiation"]
    PHONE["Android Auto phone"]

    UI --> ADB
    SESSION --> ADB
    SESSION --> IDENTITY
    SESSION --> TLS
    TLS --> TRANSPORT
    TRANSPORT <--> SOCKET
    SOCKET <--> PHONE
    SESSION --> CONN
    CONN <--> ROUTER
    SESSION --> VERSION
    VERSION <--> ROUTER
```

## Known responsibilities

  -----------------------------------------------------------------------
  Component                           Responsibility
  ----------------------------------- -----------------------------------
  `AdbManager`                        Initializes the ADB-based link and
                                      configures port forwarding used by
                                      the app.

  `HeadunitSession`                   Coordinates session connection and
                                      cleanup; current integration test
                                      calls `connect()`, `disconnect()`,
                                      and `dispose()`.

  `HeadUnitIdentity`                  Loads the head-unit certificate and
                                      private key from Flutter assets.

  `AndroidAutoTlsClient`              Handles the TLS client-side
                                      connection/handshake path.

  `SslHandshakeTransport`             Adapts TLS handshake bytes to and
                                      from the underlying transport.

  `ProtocolConnection`                Sends and receives protocol data
                                      over the established connection.

  `MessageRouter`                     Dispatches incoming protocol
                                      messages to the relevant handler.

  `VersionHandshake`                  Negotiates the Android Auto
                                      protocol version; integration test
                                      currently checks version and
                                      status.
  -----------------------------------------------------------------------

> The exact runtime ownership and call order between these classes
> should be verified against the current source. The diagram shows their
> conceptual relationships, not a guarantee that every edge is a direct
> method call.

## Connection layers

``` mermaid
flowchart LR
    A["Flutter application"] --> B["ADB port forwarding"]
    B --> C["TCP connection<br/>localhost:5277"]
    C --> D["TLS handshake"]
    D --> E["Android Auto protocol"]
    E --> F["Version negotiation"]
    F --> G["Head-unit session"]
    G -. "next milestone" .-> H["Service discovery and channels"]
```

## Current verified progress

Based on the development logs and tests reported so far:

-   TLS `SSL_do_handshake` completed successfully.
-   Protocol version negotiation succeeded for version `1.7`.
-   A real-device ADB integration test exists for the version exchange.
-   A second integration test exercises `HeadunitSession.connect()` and
    checks `session.isConnected`.

These results do not, by themselves, prove that service discovery,
channel establishment, media, navigation, or projection is implemented.

## Suggested next architecture milestone

Add explicit components (or clearly defined responsibilities) for:

1.  Control-message handling after version negotiation.
2.  Service discovery request/response parsing.
3.  Channel creation and lifecycle management.
4.  Per-service payload parsing and dispatch.
5.  Session state transitions, timeout handling, and reconnect behavior.

Keep protocol payloads and framing aligned with the C++ reference
implementation, and add tests for each protocol transition.

## Security note

The certificate/private-key pair copied from the public C++ reference is
suitable only for local interoperability experiments. Do not ship that
identity in a production APK. Flutter assets are extractable from the
built application.
