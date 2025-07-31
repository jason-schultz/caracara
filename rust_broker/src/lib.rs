use bytes::Bytes;
use dashmap::DashMap;
use futures::stream;
use sqlx::PgPool;
use std::pin::Pin;
use std::sync::Arc;
use tokio::sync::broadcast;
use tokio_stream::Stream;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::BroadcastStream;
use tonic::{Request, Response, Status};
use ulid::Ulid;

pub mod caracara {
    tonic::include_proto!("caracara");

    pub const FILE_DESCRIPTOR_SET: &[u8] =
        tonic::include_file_descriptor_set!("caracara_descriptor");
}

use caracara::caracara_server::Caracara;
use caracara::{
    ListTopicsReply, ListTopicsRequest, Message, SendMessageReply, SendMessageRequest,
    SubscribeRequest,
};

type TopicSender = broadcast::Sender<Bytes>;

#[derive(Debug)]
pub struct BrokerState {
    db_pool: PgPool,
    topics: DashMap<String, Arc<TopicSender>>,
}

impl BrokerState {
    pub fn new(db_pool: PgPool) -> Self {
        Self {
            db_pool,
            topics: DashMap::new(),
        }
    }
}

#[derive(Debug)]
pub struct BrokerService {
    state: Arc<BrokerState>,
}

impl BrokerService {
    pub fn new(state: Arc<BrokerState>) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl Caracara for BrokerService {
    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageReply>, Status> {
        let req = request.into_inner();
        let topic_name = req.topic.clone();
        let payload = Bytes::from(req.payload);
        println!(
            "[send_message] Received message for topic '{}'",
            &topic_name
        );

        let mut tx = self
            .state
            .db_pool
            .begin()
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        // Get or create the topic. We generate the ULID here in the application.
        let topic_id: Ulid =
            match sqlx::query!("SELECT id FROM topics WHERE name = $1", &topic_name)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|e| Status::internal(e.to_string()))?
            {
                Some(topic) => Ulid::from_string(&topic.id).unwrap(),
                None => {
                    let new_id = Ulid::new();
                    sqlx::query!(
                        "INSERT INTO topics (id, name) VALUES ($1, $2)",
                        new_id.to_string(),
                        &topic_name
                    )
                    .execute(&mut *tx)
                    .await
                    .map_err(|e| Status::internal(e.to_string()))?;
                    new_id
                }
            };

        // Save the message as the retained message for that topic.
        sqlx::query!(
            r#"
            INSERT INTO retained_messages (topic_id, payload) VALUES ($1, $2)
            ON CONFLICT (topic_id) DO UPDATE SET payload = EXCLUDED.payload
            "#,
            topic_id.to_string(),
            payload.as_ref()
        )
        .execute(&mut *tx)
        .await
        .map_err(|e| Status::internal(e.to_string()))?;

        tx.commit()
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        // ... broadcasting logic is unchanged ...
        if let Some(sender) = self.state.topics.get(&topic_name) {
            println!(
                "[send_message] Topic '{}' has {} active subscribers.",
                &topic_name,
                sender.receiver_count()
            );
            let _ = sender.send(payload);
        } else {
            println!(
                "[send_message] Topic '{}' has 0 active subscribers.",
                &topic_name
            );
        }

        let reply = SendMessageReply {
            status: format!("Message sent to topic '{}'", topic_name),
        };

        Ok(Response::new(reply))
    }

    // ... subscribe and list_topics methods are unchanged ...
    // The existing queries will work fine as sqlx handles the UUID type.
    type SubscribeStream = Pin<Box<dyn Stream<Item = Result<Message, Status>> + Send>>;

    async fn subscribe(
        &self,
        request: Request<SubscribeRequest>,
    ) -> Result<Response<Self::SubscribeStream>, Status> {
        let req = request.into_inner();
        let topic_name = req.topic;
        println!("[subscribe] Received request for topic '{}'", &topic_name);

        // Get the live broadcaster for this topic, creating it if it doesn't exist.
        let receiver = self
            .state
            .topics
            .entry(topic_name.clone())
            .or_insert_with(|| Arc::new(broadcast::channel(1024).0))
            .value()
            .subscribe();

        // Check for a retained message for this topic.
        let retained_message = sqlx::query!(
            r#"
            SELECT rm.payload
            FROM retained_messages rm
            JOIN topics t ON rm.topic_id = t.id
            WHERE t.name = $1
            "#,
            &topic_name
        )
        .fetch_optional(&self.state.db_pool)
        .await
        .map_err(|e| Status::internal(e.to_string()))?;

        let retained_stream = match retained_message {
            Some(record) => {
                println!("[subscribe] Found retained message for '{}'", &topic_name);
                let message = Message {
                    payload: record.payload.into(),
                };
                let stream: Pin<Box<dyn Stream<Item = Result<Message, Status>> + Send>> =
                    Box::pin(stream::once(async { Ok(message) }));
                stream
            }
            None => {
                let stream: Pin<Box<dyn Stream<Item = Result<Message, Status>> + Send>> =
                    Box::pin(stream::empty());
                stream
            }
        };

        // The main live stream.
        let live_stream = BroadcastStream::new(receiver).map(|item| {
            item.map(|bytes| Message {
                payload: bytes.into(),
            })
            .map_err(|e| Status::internal(e.to_string()))
        });

        // Chain the retained message stream with the live stream.
        let response_stream = retained_stream.chain(live_stream);

        Ok(Response::new(
            Box::pin(response_stream) as Self::SubscribeStream
        ))
    }

    async fn list_topics(
        &self,
        _request: Request<ListTopicsRequest>,
    ) -> Result<Response<ListTopicsReply>, Status> {
        println!("[list_topics] Request received to list topics.");
        let topics = sqlx::query!("SELECT name FROM topics ORDER BY name")
            .fetch_all(&self.state.db_pool)
            .await
            .map_err(|e| Status::internal(e.to_string()))?
            .into_iter()
            .map(|rec| rec.name)
            .collect();

        println!("[list_topics] Returning topics: {:?}", topics);
        let reply = ListTopicsReply { topics };
        Ok(Response::new(reply))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::OnceCell; // Use tokio's OnceCell for async initialization
    use tokio_stream::StreamExt;

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
    async fn test_live_subscription_receives_message() {
        // 1. Get the initialized pool and clean the database.
        let pool = get_pool().await;
        clean_db(pool).await;

        // 2. Create the service, cloning the connection pool.
        let state = Arc::new(BrokerState::new(pool.clone()));
        let caracara_service = BrokerService::new(state);
        let topic = "live-test-topic".to_string();

        // 3. Subscribe to a topic *before* any message is sent.
        let subscribe_request = SubscribeRequest {
            topic: topic.clone(),
        };
        let mut stream = caracara_service
            .subscribe(Request::new(subscribe_request))
            .await
            .unwrap()
            .into_inner();

        // 4. Send a message to the topic.
        let payload = b"hello from live test".to_vec();
        let send_request = SendMessageRequest {
            topic: topic.clone(),
            payload: payload.clone(),
        };
        caracara_service
            .send_message(Request::new(send_request))
            .await
            .unwrap();

        // 5. Assert that the live subscriber received the message.
        let received_msg = stream.next().await.unwrap().unwrap();
        assert_eq!(received_msg.payload, payload);

        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }

    #[tokio::test]
    async fn test_new_subscriber_receives_retained_message() {
        // 1. Get the initialized pool and clean the database.
        let pool = get_pool().await;
        clean_db(pool).await;

        // 2. Create the service, cloning the connection pool.
        let state = Arc::new(BrokerState::new(pool.clone()));
        let caracara_service = BrokerService::new(state);
        let topic = "retained-test-topic".to_string();

        // 3. Send a message *before* anyone subscribes. This creates the retained message.
        let payload = b"hello from retained test".to_vec();
        let send_request = SendMessageRequest {
            topic: topic.clone(),
            payload: payload.clone(),
        };
        caracara_service
            .send_message(Request::new(send_request))
            .await
            .unwrap();

        // 4. Now, a new client subscribes.
        let subscribe_request = SubscribeRequest {
            topic: topic.clone(),
        };
        let mut stream = caracara_service
            .subscribe(Request::new(subscribe_request))
            .await
            .unwrap()
            .into_inner();

        // 5. Assert that the new subscriber immediately receives the retained message.
        let received_msg = stream.next().await.unwrap().unwrap();
        assert_eq!(received_msg.payload, payload);

        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
}
