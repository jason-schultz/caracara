use rust_broker::{
    BrokerService, BrokerState,
    caracara::{
        SendMessageRequest, SubscribeRequest, caracara_client::CaracaraClient,
        caracara_server::CaracaraServer,
    },
};
use std::sync::Arc;
use tokio_stream::StreamExt;
use tonic::transport::Server;

#[tokio::test]
async fn test_send_and_subscribe_integration() {
    // Integration test: Spin up a server and connect with a client
    let state = Arc::new(BrokerState::default());
    let caracara_service = BrokerService::new(state);

    // Start the server in a background task
    let server = Server::builder().add_service(CaracaraServer::new(caracara_service));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server_task = tokio::spawn(
        server.serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener)),
    );

    // Connect a client
    let mut client = CaracaraClient::connect(format!("http://{}", addr))
        .await
        .unwrap();

    let topic = "integration-test-topic".to_string();

    // Subscribe
    let subscribe_request = SubscribeRequest {
        topic: topic.clone(),
    };
    let mut stream = client
        .subscribe(subscribe_request)
        .await
        .unwrap()
        .into_inner();

    // Send a message
    let payload = b"hello from integration test".to_vec();
    let send_request = SendMessageRequest {
        topic: topic.clone(),
        payload: payload.clone(),
    };
    client.send_message(send_request).await.unwrap();

    // Receive the message
    let received_msg = stream.next().await.unwrap().unwrap();
    assert_eq!(received_msg.payload, payload);

    // Clean up
    server_task.abort();
}
