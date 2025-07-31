use rust_broker::{
    BrokerService, BrokerState,
    caracara::{
        ListTopicsRequest, SendMessageRequest, SubscribeRequest, caracara_client::CaracaraClient,
        caracara_server::CaracaraServer,
    },
};
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::OnceCell; // Use tokio's OnceCell for async initialization
use tokio_stream::StreamExt;
use tonic::transport::Server;

// This OnceCell will hold our database pool.
static TEST_POOL: OnceCell<PgPool> = OnceCell::const_new();

// This async function gets or initializes the pool. It can be safely
// called from multiple tests and will only run the setup logic once.
async fn get_pool() -> &'static PgPool {
    TEST_POOL
        .get_or_init(|| async {
            // Load .env.test. Panics if it's not found or vars are missing.
            dotenvy::from_filename(".env.test").expect("Failed to load .env.test");
            let db_url =
                std::env::var("DATABASE_URL").expect("DATABASE_URL must be set in .env.test");

            // Connect and run migrations.
            let pool = PgPool::connect(&db_url)
                .await
                .expect("Failed to connect to test database");
            sqlx::migrate!("./migrations")
                .run(&pool)
                .await
                .expect("Failed to run migrations on test database");

            pool
        })
        .await
}

// Helper function to clean the database between tests for isolation.
async fn clean_db(pool: &PgPool) {
    // The order matters due to foreign key constraints.
    sqlx::query!("DELETE FROM retained_messages")
        .execute(pool)
        .await
        .unwrap();
    sqlx::query!("DELETE FROM topics")
        .execute(pool)
        .await
        .unwrap();
}

#[tokio::test]
async fn test_send_and_subscribe_integration() {
    // 1. Get the initialized pool and clean the database.
    let pool = get_pool().await;
    clean_db(pool).await;

    // 2. Create the service and start it on a random available port.
    let state = Arc::new(BrokerState::new(pool.clone()));
    let caracara_service = BrokerService::new(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server_task = tokio::spawn(
        Server::builder()
            .add_service(CaracaraServer::new(caracara_service))
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener)),
    );

    // 3. Connect a client.
    let mut client = CaracaraClient::connect(format!("http://{}", addr))
        .await
        .unwrap();

    let topic = "integration-test-topic".to_string();
    let payload = b"hello from integration test".to_vec();

    // 4. Send a message first to create the topic and the retained message.
    let send_request = SendMessageRequest {
        topic: topic.clone(),
        payload: payload.clone(),
    };
    client.send_message(send_request).await.unwrap();

    // 5. Now, subscribe to the topic.
    let subscribe_request = SubscribeRequest {
        topic: topic.clone(),
    };
    let mut stream = client
        .subscribe(subscribe_request)
        .await
        .unwrap()
        .into_inner();

    // 6. The first message we receive should be the retained message.
    let received_msg = stream.next().await.unwrap().unwrap();
    assert_eq!(received_msg.payload, payload);

    // 7. Clean up the server task and add a small delay.
    server_task.abort();
    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
}
