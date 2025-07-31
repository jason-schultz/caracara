use anyhow::Context;
use rust_broker::caracara::{FILE_DESCRIPTOR_SET, caracara_server::CaracaraServer};
use rust_broker::{BrokerService, BrokerState};
use sqlx::PgPool;
use std::sync::Arc;
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // Load environment variables from .env file
    dotenvy::dotenv().context("Failed to load .env file")?;

    println!("Starting Caracara Broker...");

    // Connect to the database
    let db_url = std::env::var("DATABASE_URL").context("DATABASE_URL must be set")?;
    let pool = PgPool::connect(&db_url)
        .await
        .context("Failed to connect to the database")?;
    println!("Database connection successful.");

    // Run database migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .context("Failed to run database migrations")?;
    println!("Database migrations ran successfully.");

    // Initialize the application state
    let state = Arc::new(BrokerState::new(pool));
    let service = BrokerService::new(state);

    let reflection_service = tonic_reflection::server::Builder::configure()
        .register_encoded_file_descriptor_set(FILE_DESCRIPTOR_SET)
        .build()
        .unwrap();

    let addr = "0.0.0.0:50051".parse().unwrap();
    println!("Caracara Broker listening on {}", addr);

    Server::builder()
        .add_service(CaracaraServer::new(service))
        .add_service(reflection_service)
        .serve(addr)
        .await?;

    Ok(())
}
