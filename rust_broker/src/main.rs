use rust_broker::{BrokerService, BrokerState, caracara::caracara_server::CaracaraServer};
use std::sync::Arc;
use tonic::transport::Server;
use tonic_reflection::server::Builder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "0.0.0.0:50051".parse()?;
    let state = Arc::new(BrokerState::default());
    let caracara_service = BrokerService::new(state);

    let reflection_service = Builder::configure()
        .register_encoded_file_descriptor_set(rust_broker::caracara::FILE_DESCRIPTOR_SET)
        .build()
        .unwrap();

    println!("Caracara server listening on {}", addr);

    Server::builder()
        .add_service(CaracaraServer::new(caracara_service))
        .add_service(reflection_service)
        .serve(addr)
        .await?;

    Ok(())
}
