# Rust Broker

The `rust_broker` is the core messaging component of the Caracara project. It is written in Rust and is responsible for handling the sending and receiving of messages. It communicates with the `ElixirControl` project using gRPC for command and control.

## Prerequisites

To build and run this project, you will need to have the Rust toolchain installed. You can install it from [rustup.rs](https://rustup.rs/).

## Building

To build the broker, run the following command in the `rust_broker` directory:

```bash
cargo build
```

For a release build, use:

```bash
cargo build --release
```

## gRPC

The gRPC service definitions are located in the `proto/` directory at the root of the Caracara project. The Rust broker implements the server-side of this gRPC contract to communicate with the Elixir control plane.
