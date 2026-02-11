defmodule ExmcViz.Cfd.Metrics do
  @moduledoc """
  In-memory metrics bus for CFD observability.

  Receives metrics from external sources and forwards them to subscribed
  Scenic scenes. Keeps a bounded history for scene rebuilds.
  """

  use GenServer

  @max_points 300

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  def publish(metric) when is_map(metric) do
    GenServer.cast(__MODULE__, {:publish, metric})
  end

  def history do
    GenServer.call(__MODULE__, :history)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subs: MapSet.new(), history: []}}
  end

  @impl true
  def handle_call(:history, _from, state), do: {:reply, state.history, state}

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | subs: MapSet.put(state.subs, pid)}}
  end

  @impl true
  def handle_cast({:publish, metric}, state) do
    Enum.each(state.subs, fn pid -> send(pid, {:cfd_metrics, metric}) end)

    history = [metric | state.history] |> Enum.take(@max_points) |> Enum.reverse()

    {:noreply, %{state | history: history}}
  end
end
