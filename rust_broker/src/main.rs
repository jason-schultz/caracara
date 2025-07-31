use rust_broker::{BrokerService, BrokerState, caracara::caracara_server::CaracaraServer};
use std::sync::Arc;
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "0.0.0.0:50051".parse()?;
    let state = Arc::new(BrokerState::default());
    let caracara_service = BrokerService::new(state);

    println!("Caracara server listening on {}", addr);

    Server::builder()
        .add_service(CaracaraServer::new(caracara_service))
        .serve(addr)
        .await?;

    Ok(())
}
