defmodule ElixirControlWeb.BrokerLive do
  use ElixirControlWeb, :live_view

  alias ElixirControl.BrokerClient
  alias ElixirControl.Subscriptions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :refresh_topics)

    socket =
      assign(socket,
        topics: [],
        messages_by_topic: %{},
        selected_topic: nil,
        subscribed_topics: MapSet.new()
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("select_topic", %{"topic" => topic}, socket) do
    # Check if we are already subscribed to this topic in this LiveView.
    unless MapSet.member?(socket.assigns.subscribed_topics, topic) do
      # If not, ensure the backend process is running and subscribe this LiveView.
      Subscriptions.ensure_subscribed(topic)
      subscribe(topic)
    end

    socket =
      socket
      |> assign(:selected_topic, topic)
      # Add the topic to our set of subscribed topics.
      # MapSet handles duplicates automatically, so this is safe to call every time.
      |> update(:subscribed_topics, &MapSet.put(&1, topic))

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_topics, socket) do
    result = BrokerClient.list_topics()

    topics =
      case result do
        {:ok, reply} -> reply.topics
        {:error, _} -> []
      end

    Process.send_after(self(), :refresh_topics, 5_000)

    {:noreply, assign(socket, :topics, topics)}
  end

  @impl true
  def handle_info({:new_message, topic, message}, socket) do
    socket =
      update(socket, :messages_by_topic, fn messages_by_topic ->
        new_messages = [message | Map.get(messages_by_topic, topic, [])] |> Enum.take(50)
        Map.put(messages_by_topic, topic, new_messages)
      end)

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # When the user closes the browser, unsubscribe from all topics.
    for topic <- socket.assigns.subscribed_topics do
      unsubscribe(topic)
    end

    :ok
  end

  defp subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(ElixirControl.PubSub, "messages:#{topic}")
  end

  defp subscribe(_), do: :ok

  defp unsubscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(ElixirControl.PubSub, "messages:#{topic}")
  end

  defp unsubscribe(_), do: :ok

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
                class={"cursor-pointer p-2 rounded hover:bg-blue-100 #{if topic == @selected_topic, do: "bg-blue-200"}"}
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
            <div class="p-2 bg-gray-100 rounded text-sm font-mono break-all">
              <%= to_string(message.payload) %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
