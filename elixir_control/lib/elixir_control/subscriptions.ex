defmodule ElixirControl.Subscriptions do
  @moduledoc """
  The main interface for creating and managing topic subscriptions.

  This module uses a `Registry` and a `DynamicSupervisor` to ensure that only
  one subscription process exists per topic across the entire application.

  The `ensure_subscribed/1` function is the public API. It can be called
  safely from any process (like a LiveView) to guarantee that a backend
  subscription is active for a given topic, starting one only if it's not
  already running.
  """

  require Logger
  use Supervisor
  alias ElixirControl.TopicSubscriber

  # Public API
  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def ensure_subscribed(topic_name) do
    # The registry ensures this is an atomic operation.
    # If the process is already running, this does nothing.
    # If not, it starts the child under our supervisor.

    Logger.info("[Subscriptions] Ensuring subscription for '#{topic_name}'")
    registry_name = Module.concat(__MODULE__, "Registry")
    via_tuple = {:via, Registry, {registry_name, topic_name}}

    child_spec = %{
      id: topic_name,
      start: {TopicSubscriber, :start_link, [[name: via_tuple, topic_name: topic_name]]}
    }

    result = DynamicSupervisor.start_child(Module.concat(__MODULE__, "Supervisor"), child_spec)
    Logger.info("[Subscriptions] start_child result for '#{topic_name}': #{inspect(result)}")

    case result do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Supervisor Callback
  @impl true
  def init(:ok) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Module.concat(__MODULE__, "Supervisor")},
      # Give the Registry its own unique name to avoid collision
      {Registry, keys: :unique, name: Module.concat(__MODULE__, "Registry")}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
