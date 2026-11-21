# 0003. Separate URL sessions per kind of traffic

Status: Accepted

## Context
A tap sized API call, a thumbnail prefetch, a large download and a server side mutation need
different timeouts and must not starve each other.

## Decision
- Interactive requests use a 15 s timeout, so a dead server never hangs a tap or the launch check.
- A low priority session (PDF thumbnail pages) has its own pool capped at 2 connections per host
  and the 60 s default. It is not `networkServiceType = .background`, which lets the system defer
  requests indefinitely, even in the foreground.
- Downloads use their own session with a 60 s inactivity timeout. `timeoutIntervalForRequest`
  resets on every packet, so it only fires on a stalled socket; on the interactive session large
  downloads timed out at 15 s and retried in a loop. Pooled connections are flushed before each
  offline run, since an idle keep alive socket may be dead.
- Mutations and uploads get 300 s: the server sends nothing until a move, copy, compress or
  upload finalises. `markingAsMutation` sets it per request; the HTTP method does not decide.
- `send` buffers at most 32 MB and only carries JSON control responses, streamed to a temporary
  file first so size is bounded by disk. Anything file sized goes through `download`, which
  streams to disk and hands the caller a file it must move or delete.
- Downloads use a completion handler task, not a download delegate: the delegate's per chunk
  callback runs on the session's serial queue and throttled the socket. Progress comes from the
  task's byte counters, which also work when the length is unknown (a streamed folder zip).

## Consequences
Temporary download files carry a fixed prefix so `SessionScratchStore` can sweep what a crash
left behind.

Code: `NetworkClient`, `NetworkClient+Live`, `FilesClient.flushDownloadConnections`.
