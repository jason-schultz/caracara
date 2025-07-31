defmodule ElixirControl.BrokerClient do
  @moduledoc """
  A client for interacting with the Caracara gRPC broker for control and monitoring.
  """

  alias Caracara.Caracara.Stub
  alias Caracara.{ListTopicsRequest, SubscribeRequest}
  # alias ElixirControl.BrokerConnection

  @host "localhost"
  @port 50051

  @doc """
  Lists all available topics on the broker.
  """
  # def list_topics do
  #   channel = BrokerConnection.channel()
  #   # This creates the correct struct
  #   request = %ListTopicsRequest{}
  #   Stub.list_topics(channel, request)
  # end

  # @doc """
  # Subscribes to a topic and returns a stream of messages.
  # """
  # def subscribe(topic) do
  #   channel = BrokerConnection.channel()
  #   request = %SubscribeRequest{topic: topic}
  #   Stub.subscribe(channel, request)
  # end

    def list_topics do
    with {:ok, channel} <- GRPC.Stub.connect("#{@host}:#{@port}") do
      request = %ListTopicsRequest{}
      Stub.list_topics(channel, request)
    end
  end

  @doc """
  Subscribes to a topic and returns a stream of messages.
  """
  def subscribe(topic) do
    with {:ok, channel} <- GRPC.Stub.connect("#{@host}:#{@port}") do
      request = %SubscribeRequest{topic: topic}
      Stub.subscribe(channel, request)
    end
  end
end
