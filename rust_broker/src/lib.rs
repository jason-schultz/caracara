use bytes::Bytes;
use dashmap::DashMap;
use std::pin::Pin;
use std::sync::Arc;
use tokio::sync::broadcast;
use tokio_stream::Stream;
use tokio_stream::wrappers::BroadcastStream;
use tonic::{Request, Response, Status};

pub mod caracara {
    tonic::include_proto!("caracara");
}

use caracara::caracara_server::{Caracara, CaracaraServer};
use caracara::{
    ListTopicsReply, ListTopicsRequest, Message, SendMessageReply, SendMessageRequest,
    SubscribeRequest,
};

type TopicSender = broadcast::Sender<Bytes>;

#[derive(Debug, Default)]
pub struct BrokerState {
    topics: DashMap<String, Arc<TopicSender>>,
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
        println!("Received message for topic '{}'", &req.topic);

        if let Some(sender) = self.state.topics.get(&req.topic) {
            sender.send(Bytes::from(req.payload)).ok();
        }

        let reply = SendMessageReply {
            status: format!("Message sent to topic '{}'", req.topic),
        };

        Ok(Response::new(reply))
    }

    type SubscribeStream = Pin<Box<dyn Stream<Item = Result<Message, Status>> + Send>>;

    async fn subscribe(
        &self,
        request: Request<SubscribeRequest>,
    ) -> Result<Response<Self::SubscribeStream>, Status> {
        let req = request.into_inner();
        let topic = req.topic;
        println!("Received subscription request for topic '{}'", &topic);

        let receiver = self
            .state
            .topics
            .entry(topic.clone())
            .or_insert_with(|| {
                println!("Creating new topic: {}", &topic);
                let (sender, _) = broadcast::channel(1024);
                Arc::new(sender)
            })
            .value()
            .subscribe();

        let stream = BroadcastStream::new(receiver);

        let response_stream = Box::pin(tokio_stream::StreamExt::map(stream, |item| {
            item.map(|bytes| Message {
                payload: bytes.into(),
            })
            .map_err(|e| Status::internal(e.to_string()))
        }));

        Ok(Response::new(response_stream as Self::SubscribeStream))
    }

    async fn list_topics(
        &self,
        _request: Request<ListTopicsRequest>,
    ) -> Result<Response<ListTopicsReply>, Status> {
        let topics = self.state.topics.iter().map(|r| r.key().clone()).collect();
        let reply = ListTopicsReply { topics };
        Ok(Response::new(reply))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_stream::StreamExt;

    #[tokio::test]
    async fn test_send_and_subscribe_unit() {
        let state = Arc::new(BrokerState::default());
        let caracara_service = BrokerService::new(state);
        let topic = "unit-test-topic".to_string();

        let subscribe_request = SubscribeRequest {
            topic: topic.clone(),
        };
        let mut stream = caracara_service
            .subscribe(Request::new(subscribe_request))
            .await
            .unwrap()
            .into_inner();

        let payload = b"hello from unit test".to_vec();
        let send_request = SendMessageRequest {
            topic: topic.clone(),
            payload: payload.clone(),
        };
        caracara_service
            .send_message(Request::new(send_request))
            .await
            .unwrap();

        let received_msg = stream.next().await.unwrap().unwrap();
        assert_eq!(received_msg.payload, payload);
    }
}
