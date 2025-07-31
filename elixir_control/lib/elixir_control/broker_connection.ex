defmodule ElixirControl.BrokerConnection do
  @moduledoc """
  A GenServer to manage the gRPC connection to the broker.
  """
  use GenServer

  alias Caracara.Caracara.Stub

  @host "localhost"
  @port 50051

  # Client API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def channel do
    GenServer.call(__MODULE__, :get_channel)
  end

  # Server Callbacks
  @impl true
  def init(:ok) do
    case GRPC.Stub.connect("#{@host}:#{@port}") do
      {:ok, channel} ->
        {:ok, channel}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_channel, _from, state) do
    {:reply, state, state}
  end
end
