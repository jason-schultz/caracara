defmodule ElixirControl.TopicSubscriber do
  @moduledoc """
  A dedicated Supervisor that ensures a single `TopicWorker` is running for a topic.

  This supervisor has only one child. Its purpose is to be started dynamically
  by the `ElixirControl.Subscriptions` manager to provide supervision and
  restart capabilities for a specific topic's worker process.
  """

  use Supervisor
  alias ElixirControl.TopicWorker
  # alias ElixirControl.BrokerClient

  # Public API
  def start_link(opts) do
    # init_arg is expected to be a keyword list, e.g. [name: via_tuple, topic_name: "foo"]
    Supervisor.start_link(__MODULE__, opts, name: opts[:name])
  end

  # Supervisor Callback
  @impl true
  def init(opts) do
    topic_name = Keyword.fetch!(opts, :topic_name)

    children = [
      # This supervisor's only child is the worker for its topic.
      {TopicWorker, topic_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
