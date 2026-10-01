# Changelog

## 1.2.1

- Fixed apps freezing on Windows while Discord is slow to read its IPC pipe. Pipe I/O is now overlapped and never blocks the calling isolate; a frame Discord leaves unread for 5 seconds fails with `DiscordConnectionException` and ends the connection, reported through `onDisconnected`.
- Fixed Discord exiting going unnoticed on Windows; the connection now closes and `onDisconnected` fires.
- Fixed `initialize()` failing when Discord answered the handshake before its write was seen to finish, and an uncaught `Connection closed before ready` error when the handshake write itself failed.

## 1.1.0

- Added `DiscordStatusDisplayType` enum to control which field is displayed in the member list status text
- Added `statusDisplayType` field to `DiscordPresence`
- Fixed overflow issue in example app

## 1.0.0

- Initial release
