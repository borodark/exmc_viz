defmodule ExmcViz.Stream.CoordinatorTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Stream.Coordinator

  test "buffers and flushes samples" do
    {:ok, coord} = Coordinator.start_link(dashboard_pid: self(), num_samples: 20)

    # Send 10 samples to trigger flush
    for i <- 1..10 do
      send(coord, {:exmc_sample, i, %{"x" => Nx.tensor(i * 1.0)}, %{divergent: false, energy: i * 1.0}})
    end

    assert_receive {:update_data, all_samples, all_stats, 10, 20}, 1000

    assert length(all_samples["x"]) == 10
    assert length(all_stats) == 10
  end

  test "flushes remaining on done" do
    {:ok, coord} = Coordinator.start_link(dashboard_pid: self(), num_samples: 5)

    for i <- 1..5 do
      send(coord, {:exmc_sample, i, %{"y" => Nx.tensor(i * 0.5)}, %{divergent: false}})
    end

    # Should get a flush at 5 (== num_samples)
    assert_receive {:update_data, _, _, 5, 5}, 1000

    send(coord, {:exmc_done, 5})
    assert_receive :sampling_complete, 1000
  end
end
