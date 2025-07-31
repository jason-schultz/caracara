defmodule ElixirControlWeb.BrokerLive do
  use ElixirControlWeb, :live_view

  alias ElixirControl.BrokerClient

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :refresh_topics)

    socket =
      assign(socket,
        topics: [],
        messages_by_topic: %{},
        selected_topic: nil,
        subscription_pid: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_topics, socket) do
    result = BrokerClient.list_topics() |> IO.inspect(label: "BrokerClient.list_topics result")

    topics =
      case result do
        {:ok, reply} -> reply.topics
        {:error, _} -> []
      end

    Process.send_after(self(), :refresh_topics, 5_000)

    {:noreply, assign(socket, :topics, topics)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Caracara Broker Control</h1>

    <div class="grid grid-cols-3 gap-6">
    <div class="col-span-1 bg-gray-50 p-4 rounded-lg">
    <h2 class="text-lg font-semibold border-b pb-2 mb-2">Topics</h2>
    <ul class="space-y-1">
      <%= if Enum.empty?(@topics) do %>
        <li class="text-gray-500">No topics found.</li>
      <% else %>
        <%= for topic <- @topics do %>
          <li
            class="cursor-pointer p-2 rounded hover:bg-blue-100"
            phx-click="select_topic"
            phx-value-topic={topic}
          >
            <%= topic %>
          </li>
        <% end %>
      <% end %>
    </ul>
    </div>

    <div class="col-span-2 bg-gray-50 p-4 rounded-lg">
    <h2 class="text-lg font-semibold border-b pb-2 mb-2">
      Messages for <%= @selected_topic || "..." %>
    </h2>
    <div class="h-96 overflow-y-auto border p-2 bg-white">
      <%= for message <- @messages_by_topic[@selected_topic] || [] do %>
        <li class="p-2 bg-gray-100 rounded text-sm font-mono">
          <%= to_string(message.payload) %>
        </li>
      <% end %>
    </div>
    </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_topic", %{"topic" => topic}, socket) do
    # Stop any existing subscription
    if socket.assigns.subscription_pid, do: Process.exit(socket.assigns.subscription_pid, :kill)

    # Start a new subscription stream in a separate process
    live_view_pid = self()

    subscription_pid =
      spawn(fn ->
        IO.puts("--- SPAWN: Subscribing to '#{topic}' ---")
        result = BrokerClient.subscribe(topic)
        IO.inspect(result, label: "SPAWN: BrokerClient.subscribe result")

        case result do
          {:ok, stream} ->
            IO.puts("SPAWN: Subscription successful. Waiting for messages...")

            stream
            |> Stream.each(fn {:ok, message} ->
              IO.inspect(message, label: "SPAWN: Received message")
              send(live_view_pid, {:new_message, topic, message})
            end)
            |> Stream.run()

            IO.puts("SPAWN: Stream finished.")

          {:error, reason} ->
            IO.puts("SPAWN: Subscription failed!")
            send(live_view_pid, {:subscription_failed, reason})
        end
      end)

    socket =
      assign(socket,
        selected_topic: topic,
        subscription_pid: subscription_pid
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, topic, message}, socket) do
    socket =
      update(socket, :messages_by_topic, fn messages_by_topic ->
        # We prepend the new message and keep the last 50
        new_messages = [message | Map.get(messages_by_topic, topic, [])] |> Enum.take(50)
        Map.put(messages_by_topic, topic, new_messages)
      end)

    {:noreply, socket}
  end

  def handle_info({:subscription_failed, reason}, socket) do
    # Handle the case where the subscription fails
    IO.inspect("Subscription failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to subscribe to topic.")}
  end
end
