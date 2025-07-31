defmodule ElixirControlWeb.BrokerLive do
  use ElixirControlWeb, :live_view

  alias ElixirControl.BrokerClient

  @impl true
  def mount(_params, _session, socket) do
    topics =
      case BrokerClient.list_topics() do
        {:ok, reply} -> reply.topics
        {:error, _} -> []
      end

    socket =
      assign(socket,
        topics: topics,
        messages: [],
        selected_topic: nil,
        subscription_pid: nil
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-4">Caracara Broker Control</h1>

    <div class="grid grid-cols-3 gap-6">
      <div class="col-span-1">
        <h2 class="text-xl font-semibold">Topics</h2>
        <ul class="list-disc list-inside mt-2">
          <.link
            :for={topic <- @topics}
            phx-click="select_topic"
            phx-value-topic={topic}
            class={"cursor-pointer p-2 rounded #{if topic == @selected_topic, do: "bg-blue-500 text-white", else: "hover:bg-gray-200"}"}
          >
            <li><%= topic %></li>
          </.link>
        </ul>
        <p :if={@topics == []} class="text-gray-500">No topics found.</p>
      </div>

      <div class="col-span-2">
        <h2 class="text-xl font-semibold">
          Messages for <span class="font-bold text-blue-600"><%= @selected_topic || "..." %></span>
        </h2>
        <div id="messages" class="mt-2 p-4 border rounded-lg h-96 overflow-y-auto bg-gray-50">
          <div :for={msg <- @messages} class="p-2 border-b">
            <p class="font-mono text-sm"><%= Base.encode64(msg.payload) %></p>
          </div>
          <p :if={@messages == []} class="text-gray-500">
            <%= if @selected_topic, do: "No messages yet.", else: "Select a topic to view messages." %>
          </p>
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
        case BrokerClient.subscribe(topic) do
          {:ok, stream} ->
            stream
            |> Enum.each(fn {:ok, message} ->
              send(live_view_pid, {:new_message, message})
            end)

          {:error, reason} ->
            send(live_view_pid, {:subscription_failed, reason})
        end
      end)

    socket =
      assign(socket,
        selected_topic: topic,
        messages: [],
        subscription_pid: subscription_pid
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Prepend new message and cap the list at 50
    messages = [message | socket.assigns.messages] |> Enum.take(50)
    {:noreply, assign(socket, :messages, messages)}
  end

  def handle_info({:subscription_failed, reason}, socket) do
    # Handle the case where the subscription fails
    IO.inspect("Subscription failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to subscribe to topic.")}
  end
end
