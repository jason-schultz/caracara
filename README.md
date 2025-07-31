# Caracara

Caracara is a distributed, fault-tolerant messaging system, similar to Apache Kafka, designed for high-throughput data streaming. It is composed of a Rust-based message broker for performance-critical operations and an Elixir-based control plane for management and monitoring.

## Architecture

The project is divided into two main components:

*   **`rust_broker`**: The core of Caracara. A high-performance message broker written in Rust, responsible for handling message persistence, replication, and delivery.
*   **`elixir_control`**: A web-based control panel built with the Phoenix framework in Elixir. It provides a user interface for monitoring the cluster's health, managing topics, and observing message flow.

These two components communicate with each other via gRPC. The service definitions are located in the `proto/` directory.

## Components

### Rust Broker

The `rust_broker` is the engine of Caracara. For more information on how to build and run it, please see the [rust_broker README](./rust_broker/README.md).

### Elixir Control

The `elixir_control` application provides a web interface for managing the Caracara cluster. For setup and usage instructions, refer to the [elixir_control README](./elixir_control/README.md).

## Getting Started

To get the entire Caracara system running, you will need to build and run each component separately. Please refer to the README file in each component's directory for specific instructions.

1.  **Start the Rust Broker**: Follow the instructions in `rust_broker/README.md`.
2.  **Start the Elixir Control Plane**: Follow the instructions in `elixir_control/README.md`.

## gRPC API

The gRPC API contract between the `rust_broker` and `elixir_control` is defined in `proto/caracara.proto`.
