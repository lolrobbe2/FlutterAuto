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
    participant TCP as TCP socket :5277
    participant TLS as TLS client / transport
    participant PC as ProtocolConnection
    participant Router as MessageRouter
    participant VH as VersionHandshake
    participant Identity as HeadUnitIdentity

    Test->>Session: connect()
    Session->>ADB: initialize/configure ADB link
    ADB->>Phone: ADB device commands / forwarding
    Session->>Identity: load certificate and private key
    Session->>TCP: connect to 127.0.0.1:5277
    TCP-->>Phone: forwarded TCP stream

    Session->>TLS: start TLS handshake
    TLS->>Phone: TLS handshake records
    Phone-->>TLS: TLS handshake records
    TLS-->>Session: handshake completed
    Note over TLS,Phone: TLS handshake has succeeded in development logs

    Session->>PC: initialize protocol connection
    Session->>Router: set up message routing
    Session->>VH: run version negotiation
    VH->>Router: send version negotiation message
    Router->>PC: send protocol message
    PC->>Phone: framed protocol bytes
    Phone-->>PC: response bytes
    PC-->>Router: decoded/routed message
    Router-->>VH: version response
    VH-->>Session: VersionHandshakeResult
    Session-->>Test: connect result / connected state

    Note over Session,Phone: Service discovery and service-channel setup must be verified separately
```

## Simplified state machine

``` mermaid
stateDiagram-v2
    [*] --> ADBSetup
    ADBSetup --> TCPConnecting: ADB forwarding ready
    TCPConnecting --> TLSHandshake: TCP connected
    TLSHandshake --> VersionNegotiation: TLS succeeds
    TLSHandshake --> Failed: TLS error or timeout
    VersionNegotiation --> SessionReady: valid version response
    VersionNegotiation --> Failed: invalid response or timeout
    SessionReady --> ServiceDiscovery: next implementation milestone
    ServiceDiscovery --> ChannelsReady: services/channels established
    ServiceDiscovery --> Failed: protocol error or timeout
    ChannelsReady --> Disconnecting: disconnect requested
    SessionReady --> Disconnecting: disconnect requested
    Failed --> Disconnecting: cleanup
    Disconnecting --> [*]
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
