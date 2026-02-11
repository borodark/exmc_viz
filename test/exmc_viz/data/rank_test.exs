defmodule ExmcViz.Data.RankTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Data.{Prepare, RankData}

  describe "prepare_ranks" do
    test "2 chains of 100 samples, ranks span 0..199" do
      chain1 = %{"x" => Nx.tensor(Enum.map(1..100, fn _ -> :rand.normal() end))}
      chain2 = %{"x" => Nx.tensor(Enum.map(1..100, fn _ -> :rand.normal() end))}

      [rank_data] = Prepare.prepare_ranks([chain1, chain2])

      assert %RankData{} = rank_data
      assert rank_data.name == "x"
      assert rank_data.num_chains == 2
      assert rank_data.num_bins == 20

      # Total counts across all chains should equal total samples
      total = rank_data.rank_histograms |> List.flatten() |> Enum.sum()
      assert total == 200
    end

    test "histogram bins have expected count for well-mixed chains" do
      # Two chains from same distribution should produce ~uniform rank histograms
      :rand.seed(:exsss, 42)
      n = 500
      chain1 = %{"x" => Nx.tensor(Enum.map(1..n, fn _ -> :rand.normal() end))}
      chain2 = %{"x" => Nx.tensor(Enum.map(1..n, fn _ -> :rand.normal() end))}

      [rank_data] = Prepare.prepare_ranks([chain1, chain2], 10)

      # 50 per chain per bin
      expected_per_bin = n / 10

      for hist <- rank_data.rank_histograms do
        for count <- hist do
          # With 500 samples per chain and 10 bins, expect ~50 per bin
          # Allow generous tolerance for randomness
          assert count > 20, "bin count #{count} too low (expected ~#{expected_per_bin})"
          assert count < 80, "bin count #{count} too high (expected ~#{expected_per_bin})"
        end
      end
    end

    test "poorly mixed chains show non-uniform ranks" do
      # Chain 1: all positive values, Chain 2: all negative values
      chain1 = %{"x" => Nx.tensor(Enum.map(1..100, fn i -> i * 1.0 end))}
      chain2 = %{"x" => Nx.tensor(Enum.map(1..100, fn i -> -i * 1.0 end))}

      [rank_data] = Prepare.prepare_ranks([chain1, chain2], 10)

      # Chain 1 should have all high ranks, chain 2 all low ranks
      # So chain1's histogram should be concentrated in upper bins
      [hist1, _hist2] = rank_data.rank_histograms

      lower_half_1 = Enum.take(hist1, 5) |> Enum.sum()
      upper_half_1 = Enum.drop(hist1, 5) |> Enum.sum()

      # Chain 1 (positive values) should have most ranks in upper half
      assert upper_half_1 > lower_half_1
    end

    test "multiple variables" do
      chain1 = %{
        "a" => Nx.tensor(Enum.map(1..50, fn _ -> :rand.normal() end)),
        "b" => Nx.tensor(Enum.map(1..50, fn _ -> :rand.normal() end))
      }

      chain2 = %{
        "a" => Nx.tensor(Enum.map(1..50, fn _ -> :rand.normal() end)),
        "b" => Nx.tensor(Enum.map(1..50, fn _ -> :rand.normal() end))
      }

      result = Prepare.prepare_ranks([chain1, chain2])
      assert length(result) == 2
      names = Enum.map(result, & &1.name) |> Enum.sort()
      assert names == ["a", "b"]
    end

    test "RankData struct fields are populated" do
      chain1 = %{"x" => Nx.tensor([1.0, 2.0, 3.0])}
      chain2 = %{"x" => Nx.tensor([4.0, 5.0, 6.0])}

      [rd] = Prepare.prepare_ranks([chain1, chain2], 3)
      assert rd.name == "x"
      assert rd.num_chains == 2
      assert rd.num_bins == 3
      assert length(rd.rank_histograms) == 2
      assert Enum.all?(rd.rank_histograms, fn h -> length(h) == 3 end)
    end
  end
end
