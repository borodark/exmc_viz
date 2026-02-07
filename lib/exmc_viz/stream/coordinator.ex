defmodule ExmcViz.Stream.Coordinator do
  @moduledoc """
  GenServer that buffers incoming MCMC samples and periodically flushes
  them to the `LiveDashboard` scene for visualization updates.

  Sits between the sampler task and the Scenic scene:

      Sampler Task  --{:exmc_sample, ...}-->  Coordinator  --{:update_data, ...}-->  LiveDashboard

  Accumulates samples into `all_samples` (a `%{name => [float()]}` map)
  and `all_stats` (a list of step stat maps). Flushes every 10 samples
  or when the final sample arrives, sending the full accumulated trace
  to the dashboard so it can rebuild the graph.

  Also forwards `{:exmc_done, total}` as `:sampling_complete` so the
  dashboard can update its title.
  """
  use GenServer

  @flush_size 10

  def start_link(opts) do
    dashboard_pid = Keyword.fetch!(opts, :dashboard_pid)
    num_samples = Keyword.fetch!(opts, :num_samples)
    GenServer.start_link(__MODULE__, {dashboard_pid, num_samples})
  end

  @impl GenServer
  def init({dashboard_pid, num_samples}) do
    state = %{
      dashboard_pid: dashboard_pid,
      num_samples: num_samples,
      buffer: [],
      all_samples: %{},
      all_stats: [],
      count: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:exmc_sample, _i, point_map, step_stat}, state) do
    buffer = [{point_map, step_stat} | state.buffer]
    count = state.count + 1

    if length(buffer) >= @flush_size or count >= state.num_samples do
      # Merge buffered samples into accumulated trace
      {all_samples, all_stats} = flush_buffer(buffer, state.all_samples, state.all_stats)

      # Send update to dashboard
      send(state.dashboard_pid, {:update_data, all_samples, all_stats, count, state.num_samples})

      {:noreply, %{state | buffer: [], all_samples: all_samples, all_stats: all_stats, count: count}}
    else
      {:noreply, %{state | buffer: buffer, count: count}}
    end
  end

  @impl GenServer
  def handle_info({:exmc_done, _total}, state) do
    # Final flush if any remaining
    if state.buffer != [] do
      {all_samples, all_stats} = flush_buffer(state.buffer, state.all_samples, state.all_stats)
      send(state.dashboard_pid, {:update_data, all_samples, all_stats, state.count, state.num_samples})
    end

    send(state.dashboard_pid, :sampling_complete)
    {:noreply, state}
  end

  defp flush_buffer(buffer, all_samples, all_stats) do
    # Buffer is in reverse order, reverse it
    buffer = Enum.reverse(buffer)

    new_stats = Enum.map(buffer, fn {_pm, stat} -> stat end)
    all_stats = all_stats ++ new_stats

    all_samples =
      Enum.reduce(buffer, all_samples, fn {point_map, _stat}, acc ->
        Enum.reduce(point_map, acc, fn {name, tensor}, acc ->
          existing = Map.get(acc, name, [])
          val = Nx.to_number(tensor)
          Map.put(acc, name, existing ++ [val])
        end)
      end)

    {all_samples, all_stats}
  end
end
