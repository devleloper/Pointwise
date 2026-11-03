# Security Policy

Pointwise sits in the path of your mouse input (scroll events) and holds Accessibility access, so security and privacy reports are taken seriously.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's [private vulnerability reporting](https://github.com/devleloper/Pointwise/security/advisories/new) instead. Include:

- what you found and its impact;
- steps to reproduce, macOS and Pointwise versions;
- a suggested fix, if you have one.

You will get an acknowledgement within a week. Once a fix is released, the advisory is published with credit, unless you prefer to stay anonymous.

## What counts

- Any way Pointwise could observe, retain or leak keyboard input or other input beyond scroll events and mouse-button presses.
- Any network activity by Pointwise.
- Ways to make Pointwise inject, block, duplicate or alter input other than the configured scroll behaviour.
- Ways to leave a device in a changed state after Pointwise quits or is paused.
- Privilege or permission misuse.
