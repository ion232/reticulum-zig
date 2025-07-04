# Overview

An implementation of [Reticulum](https://github.com/markqvist/Reticulum) in [Zig](https://ziglang.org/) targeting operating systems and embedded devices.

# Structure

## App

- `app/` is the classic Reticulum app for standard operating systems.
- Currently this is fairly empty as I work on the core functionality.

## Core

- `core/` is the core functionality of Reticulum.
- Provides the means to setup nodes and their interfaces without coupling to operating system calls.
- Built as a module for use in embedded and operating systems.
- The crypto implementation currently leverages std.crypto from the zig std library.
- Eventually I will provide an option to use OpenSSL.

## Boards

- `boards/` stores image setups for embedded devices that users can build with one command.
- Makes use of [microzig](https://github.com/ZigEmbeddedGroup/microzig) as a submodule for targeting embedded devices.
- Currently there is a very simple proof of concept for the pico.
- It makes an identity, endpoint and announce packet and sends it over serial.
- The image can be built by running `zig build -Doptimize=ReleaseSafe pico` from `boards`.

## Test

- `test/` stores integration tests for core.
- Eventually these will be done via deterministic simulation.
- This will provide strong assurances on behaviour and make debugging much simpler. 

# Goals

- Parity to reference implementation in core behaviour.
- Cross-platform app for running on operating systems.
- Providing one-line image builds of Reticulum for embedded devices.
- Option of using OpenSSL for crypto.
- Determinstic simulation testing.
- Comprehensive integration tests.

# Anti-goals

- Exact parity to reference implementation in terminology/structure.

# Licence

- Currently under Apache 2.0 for now; if I move over to the Reticulum licence at some point, it will only be after significant thought and consideration.
