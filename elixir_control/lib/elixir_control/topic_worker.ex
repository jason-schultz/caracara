defmodule ElixirControl.TopicWorker do
  @moduledoc """
  A GenServer worker that manages a persistent gRPC subscription for a single topic.

  This process is responsible for connecting to the gRPC stream, consuming messages,
  and broadcasting them to the local `Phoenix.PubSub` system. If the stream
  disconnects for any reason, this worker will automatically attempt to reconnect
  after a short delay.

  It is designed to be supervised by a `ElixirControl.TopicSubscriber` supervisor.
  """

  use GenServer
  require Logger
  alias ElixirControl.BrokerClient

  def start_link(topic_name) do
    GenServer.start_link(__MODULE__, topic_name)
  end

  # Server Callbacks
  @impl true
  def init(topic_name) do
    # Start the work immediately. The work loop runs in this process.
    # We send a message to ourselves to start the first attempt.
    send(self(), :subscribe)
    {:ok, %{topic_name: topic_name}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    Logger.info("[TopicWorker #{state.topic_name}] Attempting to subscribe...")

    case BrokerClient.subscribe(state.topic_name) do
      {:ok, stream} ->
        Logger.info(
          "[TopicWorker #{state.topic_name}] Subscription successful. Consuming stream."
        )

        # This call is blocking, which is what we want.
        # It will consume the stream until it ends.
        consume_stream(stream, state.topic_name)

        # When the stream ends, we schedule a reconnect.
        Logger.warning("[TopicWorker #{state.topic_name}] Stream ended. Reconnecting in 5s.")
        Process.send_after(self(), :subscribe, 5_000)

      {:error, reason} ->
        Logger.error(
          "[TopicWorker #{state.topic_name}] Subscription failed. Reason: #{inspect(reason)}. Retrying in 5s."
        )

        Process.send_after(self(), :subscribe, 5_000)
    end

    {:noreply, state}
  end

  defp consume_stream(stream, topic_name) do
    stream
    |> Stream.each(fn {:ok, message} ->
      Phoenix.PubSub.broadcast(
        ElixirControl.PubSub,
        "messages:#{topic_name}",
        {:new_message, topic_name, message}
      )
    end)
    |> Stream.run()
  end
end
