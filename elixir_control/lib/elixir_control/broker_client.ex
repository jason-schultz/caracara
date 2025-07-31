defmodule ElixirControl.BrokerClient do
  @moduledoc """
  A client for interacting with the Caracara gRPC broker for control and monitoring.
  """

  alias Caracara.Caracara.Stub
  alias Caracara.{ListTopicsRequest, SubscribeRequest}
  alias ElixirControl.BrokerConnection

  @doc """
  Lists all available topics on the broker.
  """
  def list_topics do
    channel = BrokerConnection.channel()
    # request = ListTopicsRequest.new() # This creates the correct struct
    request = %ListTopicsRequest{}
    # Stub.list_topics()
    Stub.list_topics(channel, request)
  end

  @doc """
  Subscribes to a topic and returns a stream of messages.
  """
  def subscribe(topic) do
    channel = BrokerConnection.channel()
    request = SubscribeRequest.new(topic: topic)
    Stub.subscribe(channel, request)
  end
end
