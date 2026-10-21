# FlutterAuto --- Connection and Handshake Flow

> This document describes the currently known connection sequence. It
> separates confirmed behavior from protocol steps that still need
> verification in the implementation.

## Sequence diagram

``` mermaid

sequenceDiagram
    autonumber
    participant Test as Integration test
    participant Session as HeadunitSession
    participant ADB as AdbManager
    participant Phone as Android Auto phone
    participant Socket as TCP socket
    participant PC as ProtocolConnection
    participant Router as MessageRouter
    participant VH as VersionHandshake
    participant Identity as HeadUnitIdentity
    participant TLS as AndroidAutoTlsClient

    Test->>Session: connect()
    Session->>Session: State = connecting

    opt configureAdb = true
        Session->>ADB: initializeAndroidAutoLink()
        ADB-->>Session: ADB setup complete
    end

    Session->>Socket: Socket.connect(127.0.0.1:5277)
    Socket-->>Session: TCP socket connected

    Session->>PC: ProtocolConnection(socket)
    Session->>Router: MessageRouter(protocolConnection)
    Session->>Session: State = negotiatingVersion

    Note over VH,Router: 1. Version negotiation — before TLS
    Session->>VH: run()
    VH->>Router: Send version request
    Router->>PC: Send protocol message
    PC->>Phone: Protocol bytes over TCP
    Phone-->>PC: Version response bytes
    PC-->>Router: Incoming response
    Router-->>VH: Route version response
    VH-->>Session: VersionHandshakeResult

    Session->>PC: Check connection is still open
    Session->>Identity: ensureIdentity()
    Identity-->>Session: Identity ready
    Session->>Identity: debugCertificatePem()

    Note over TLS,Phone: 2. TLS handshake — after version negotiation
    Session->>TLS: Create TLS client and transport
    Session->>TLS: connect()
    TLS->>Phone: TLS handshake records
    Phone-->>TLS: TLS handshake records
    TLS-->>Session: TLS handshake completed

    Session->>PC: Check connection is still open
    Session->>Session: State = connected
    Session-->>Test: Return VersionHandshakeResult
```

## Simplified state machine

``` mermaid

stateDiagram-v2
    [*] --> Disconnected
    Disconnected --> Connecting: connect()

    Connecting --> NegotiatingVersion: TCP connected and router initialized
    Connecting --> Failed: ADB or TCP setup fails

    NegotiatingVersion --> TLSHandshake: Version negotiation succeeds
    NegotiatingVersion --> Failed: Version negotiation fails

    TLSHandshake --> Connected: TLS succeeds and connection remains open
    TLSHandshake --> Failed: TLS or connection check fails

    Connected --> Disconnecting: disconnect()
    Connecting --> Disconnecting: disconnect()
    NegotiatingVersion --> Disconnecting: disconnect()
    Failed --> Disconnecting: disconnect()

    Disconnecting --> Disconnected: Resources closed
    Connected --> Disconnected: TCP connection closes

    Connected --> ServiceDiscovery: Future milestone
    ServiceDiscovery --> ChannelsReady: Services and channels established

```

`ServiceDiscovery` and `ChannelsReady` are target milestones in this
diagram, not claims that the current implementation already reaches
them.

## What is confirmed so far

The development logs reported:

``` text
[TLS] SSL_do_handshake result=1, error=0
[TLS] Handshake completed successfully.
Version negotiation succeeded: Instance of 'VersionHandshakeResult'
```

This confirms the TLS handshake and indicates that version negotiation
returned successfully. The log alone does not show the negotiated
version/status fields or prove that the complete head-unit protocol
session is ready.

The integration test for `VersionHandshake` checks:

-   `result.majorVersion > 0`
-   `result.status.value == 0`

The `HeadunitSession` integration test checks `session.isConnected`
after `session.connect()` returns. Check the implementation to ensure
that this state means more than "socket/TLS connected."

## Failure boundaries to test

  -----------------------------------------------------------------------
  Stage                               Useful failure tests
  ----------------------------------- -----------------------------------
  ADB setup                           ADB missing, phone unauthorized,
                                      forwarding command fails

  TCP connect                         Port not forwarded, connection
                                      refused, timeout

  TLS                                 Peer closes connection, malformed
                                      TLS data, handshake timeout

  Version negotiation                 Unexpected message, nonzero status,
                                      unsupported version, timeout

  Session cleanup                     Disconnect during handshake,
                                      repeated disconnect, disposal after
                                      failure

  Future service discovery            Unknown service, malformed payload,
                                      channel-open rejection, phone
                                      disconnect
  -----------------------------------------------------------------------

## Operational notes

-   Keep packet/byte dumps at `fine` log level.
-   Include the stage and relevant error/stack trace in failure logs.
-   Always close the router, protocol connection, socket, and TLS
    resources according to their ownership rules.
-   Treat the reference certificate/private key as development-only. Do
    not bundle the public reference identity in a production app.
