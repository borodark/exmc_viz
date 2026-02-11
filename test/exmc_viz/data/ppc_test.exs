defmodule ExmcViz.Data.PPCTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Data.{Prepare, PPCData}

  describe "prepare_ppc" do
    test "observed histogram counts sum to number of observations" do
      obs = %{"y" => Nx.tensor([1.0, 2.0, 3.0, 4.0, 5.0])}
      pred = %{"y" => Nx.tensor([[1.1, 2.1, 3.1, 4.1, 5.1], [0.9, 1.9, 2.9, 3.9, 4.9]])}

      [ppc] = Prepare.prepare_ppc(obs, pred, 5)

      obs_total = Enum.sum(ppc.observed_histogram)
      assert obs_total == 5
    end

    test "predictive histograms: one per sample, counts sum correctly" do
      obs = %{"y" => Nx.tensor([1.0, 2.0, 3.0])}
      pred = %{"y" => Nx.tensor([[1.0, 2.0, 3.0], [1.5, 2.5, 3.5], [0.5, 1.5, 2.5]])}

      [ppc] = Prepare.prepare_ppc(obs, pred, 5)

      assert length(ppc.predictive_histograms) == 3

      for pred_hist <- ppc.predictive_histograms do
        total = Enum.sum(pred_hist)
        assert total == 3
      end
    end

    test "observed and predictive use same bin edges" do
      obs = %{"y" => Nx.tensor([1.0, 2.0, 3.0])}
      pred = %{"y" => Nx.tensor([[1.0, 2.0, 3.0]])}

      [ppc] = Prepare.prepare_ppc(obs, pred, 10)

      assert length(ppc.bin_edges) == 11
      assert length(ppc.observed_histogram) == 10
      assert length(hd(ppc.predictive_histograms)) == 10
    end

    test "PPCData struct fields are populated" do
      obs = %{"y" => Nx.tensor([1.0, 2.0])}
      pred = %{"y" => Nx.tensor([[1.0, 2.0]])}

      [ppc] = Prepare.prepare_ppc(obs, pred, 5)

      assert %PPCData{} = ppc
      assert ppc.obs_name == "y"
      assert ppc.num_bins == 5
      assert is_list(ppc.bin_edges)
      assert is_integer(ppc.max_count)
      assert ppc.max_count >= 0
    end

    test "single observation, single prediction" do
      obs = %{"y" => Nx.tensor([3.0])}
      pred = %{"y" => Nx.tensor([[3.5]])}

      [ppc] = Prepare.prepare_ppc(obs, pred, 5)

      obs_total = Enum.sum(ppc.observed_histogram)
      assert obs_total == 1
      pred_total = Enum.sum(hd(ppc.predictive_histograms))
      assert pred_total == 1
    end
  end
end
