defmodule ExmcViz.Data.PrepareTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Data.{Prepare, VarData}

  describe "from_trace/1" do
    test "converts single-variable trace" do
      samples = for _ <- 1..100, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      [vd] = Prepare.from_trace(trace)

      assert %VarData{} = vd
      assert vd.name == "x"
      assert vd.n_samples == 100
      assert is_float(vd.mean)
      assert is_float(vd.std)
      assert is_float(vd.ess)
      assert is_list(vd.samples)
      assert length(vd.samples) == 100
      assert is_nil(vd.chains)
      assert is_nil(vd.rhat)
    end

    test "converts multi-variable trace sorted by name" do
      trace = %{
        "beta" => Nx.tensor(for(_ <- 1..50, do: :rand.normal())),
        "alpha" => Nx.tensor(for(_ <- 1..50, do: :rand.normal()))
      }

      var_data = Prepare.from_trace(trace)

      assert length(var_data) == 2
      assert hd(var_data).name == "alpha"
      assert List.last(var_data).name == "beta"
    end

    test "computes quantiles" do
      # Uniform 0..99
      samples = Enum.map(0..99, &(&1 * 1.0))
      trace = %{"u" => Nx.tensor(samples)}

      [vd] = Prepare.from_trace(trace)

      assert_in_delta vd.quantiles.q50, 49.5, 1.0
      assert vd.quantiles.q5 < vd.quantiles.q25
      assert vd.quantiles.q25 < vd.quantiles.q50
      assert vd.quantiles.q50 < vd.quantiles.q75
      assert vd.quantiles.q75 < vd.quantiles.q95
    end

    test "computes histogram with bins" do
      samples = for _ <- 1..200, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      [vd] = Prepare.from_trace(trace)

      assert is_map(vd.histogram)
      assert is_list(vd.histogram.bins)
      assert length(vd.histogram.bins) == 30
      assert vd.histogram.max_count > 0

      # Total count across bins equals n_samples
      total = Enum.sum(Enum.map(vd.histogram.bins, fn {_, _, c} -> c end))
      assert total == 200
    end

    test "computes ACF" do
      samples = for _ <- 1..100, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      [vd] = Prepare.from_trace(trace)

      assert is_list(vd.acf)
      # First ACF value (lag 0) should be 1.0
      assert_in_delta hd(vd.acf), 1.0, 0.001
      # Max lag should be min(40, n-1)
      assert length(vd.acf) == 41
    end
  end

  describe "from_chains/1" do
    test "combines multiple chains" do
      chain1 = %{"x" => Nx.tensor(for(_ <- 1..50, do: :rand.normal()))}
      chain2 = %{"x" => Nx.tensor(for(_ <- 1..50, do: :rand.normal()))}

      [vd] = Prepare.from_chains([chain1, chain2])

      assert %VarData{} = vd
      assert vd.name == "x"
      assert vd.n_samples == 100
      assert is_list(vd.chains)
      assert length(vd.chains) == 2
      assert length(hd(vd.chains)) == 50
      assert is_float(vd.rhat)
    end
  end

  describe "from_trace/2 with stats" do
    test "extracts divergent indices from stats" do
      samples = for _ <- 1..50, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      stats = %{
        sample_stats:
          [
            %{divergent: false},
            %{divergent: true},
            %{divergent: false},
            %{divergent: true}
          ] ++ List.duplicate(%{divergent: false}, 46)
      }

      [vd] = Prepare.from_trace(trace, stats)

      assert vd.divergent_indices == [1, 3]
    end

    test "returns nil divergent_indices when no divergences" do
      samples = for _ <- 1..20, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      stats = %{
        sample_stats: List.duplicate(%{divergent: false}, 20)
      }

      [vd] = Prepare.from_trace(trace, stats)

      assert is_nil(vd.divergent_indices)
    end

    test "returns nil divergent_indices when stats is nil" do
      samples = for _ <- 1..20, do: :rand.normal()
      trace = %{"x" => Nx.tensor(samples)}

      [vd] = Prepare.from_trace(trace, nil)

      assert is_nil(vd.divergent_indices)
    end
  end

  describe "compute_hdi/3" do
    test "94% HDI contains roughly 94% of samples" do
      sorted = Enum.map(0..99, &(&1 * 1.0))
      {lo, hi} = Prepare.compute_hdi(sorted, 100, 0.94)

      # The interval should span about 94 values
      width = hi - lo
      assert width >= 90.0
      assert width <= 99.0
      assert lo >= 0.0
      assert hi <= 99.0
    end

    test "50% HDI is narrower than 94% HDI" do
      sorted = Enum.sort(for _ <- 1..200, do: :rand.normal())
      n = length(sorted)

      {lo94, hi94} = Prepare.compute_hdi(sorted, n, 0.94)
      {lo50, hi50} = Prepare.compute_hdi(sorted, n, 0.50)

      assert hi50 - lo50 < hi94 - lo94
    end

    test "HDI of single value returns that value" do
      sorted = [5.0]
      {lo, hi} = Prepare.compute_hdi(sorted, 1, 0.94)

      assert lo == 5.0
      assert hi == 5.0
    end
  end

  describe "prepare_forest/1" do
    test "returns ForestData for each variable" do
      trace = %{
        "alpha" => Nx.tensor(for(_ <- 1..100, do: :rand.normal())),
        "beta" => Nx.tensor(for(_ <- 1..100, do: :rand.normal() + 2.0))
      }

      forest = Prepare.prepare_forest(trace)

      assert length(forest) == 2
      assert hd(forest).name == "alpha"
      assert List.last(forest).name == "beta"

      fd = hd(forest)
      assert is_float(fd.mean)
      assert is_tuple(fd.hdi_94)
      assert is_tuple(fd.hdi_50)

      {lo94, hi94} = fd.hdi_94
      {lo50, hi50} = fd.hdi_50

      # 50% interval is inside 94% interval
      assert lo50 >= lo94
      assert hi50 <= hi94
    end
  end

  describe "prepare_pairs/1" do
    test "returns PairData with correct structure" do
      trace = %{
        "a" => Nx.tensor(for(_ <- 1..100, do: :rand.normal())),
        "b" => Nx.tensor(for(_ <- 1..100, do: :rand.normal())),
        "c" => Nx.tensor(for(_ <- 1..100, do: :rand.normal()))
      }

      pd = Prepare.prepare_pairs(trace)

      assert %ExmcViz.Data.PairData{} = pd
      assert pd.var_names == ["a", "b", "c"]
      assert length(pd.var_samples["a"]) == 100
      assert is_map(pd.correlations)
      assert is_map(pd.histograms)

      # Correlations for all off-diagonal pairs
      assert Map.has_key?(pd.correlations, {"a", "b"})
      assert Map.has_key?(pd.correlations, {"b", "a"})
      assert Map.has_key?(pd.correlations, {"a", "c"})
    end

    test "self-correlation is not stored (diagonal)" do
      trace = %{
        "x" => Nx.tensor(for(_ <- 1..50, do: :rand.normal()))
      }

      pd = Prepare.prepare_pairs(trace)

      refute Map.has_key?(pd.correlations, {"x", "x"})
    end
  end

  describe "pearson_correlation/2" do
    test "perfect positive correlation" do
      xs = Enum.map(1..100, &(&1 * 1.0))
      ys = Enum.map(1..100, &(&1 * 2.0 + 3.0))

      r = Prepare.pearson_correlation(xs, ys)
      assert_in_delta r, 1.0, 0.001
    end

    test "perfect negative correlation" do
      xs = Enum.map(1..100, &(&1 * 1.0))
      ys = Enum.map(1..100, &(-&1 * 1.0))

      r = Prepare.pearson_correlation(xs, ys)
      assert_in_delta r, -1.0, 0.001
    end

    test "uncorrelated random data near zero" do
      :rand.seed(:exsss, 42)
      xs = for _ <- 1..1000, do: :rand.normal()
      ys = for _ <- 1..1000, do: :rand.normal()

      r = Prepare.pearson_correlation(xs, ys)
      assert abs(r) < 0.15
    end
  end

  describe "prepare_energy/1" do
    test "extracts energy data from stats" do
      sample_stats =
        Enum.map(1..50, fn i -> %{energy: i * 1.0, divergent: false} end)

      stats = %{sample_stats: sample_stats}
      ed = Prepare.prepare_energy(stats)

      assert %ExmcViz.Data.EnergyData{} = ed
      assert length(ed.energies) == 50
      assert length(ed.transitions) == 49
      assert ed.max_count > 0
    end

    test "returns nil when stats is nil" do
      assert is_nil(Prepare.prepare_energy(nil))
    end

    test "returns nil when no energy in sample_stats" do
      stats = %{sample_stats: [%{divergent: false}, %{divergent: false}]}
      assert is_nil(Prepare.prepare_energy(stats))
    end
  end

  describe "compute_histogram/2" do
    test "all values land in bins" do
      values = Enum.map(1..100, &(&1 * 1.0))
      %{bins: bins} = Prepare.compute_histogram(values, 10)

      total = Enum.sum(Enum.map(bins, fn {_, _, c} -> c end))
      assert total == 100
    end

    test "handles identical values" do
      values = List.duplicate(5.0, 50)
      %{bins: bins, max_count: max_count} = Prepare.compute_histogram(values, 10)

      assert max_count == 50
      total = Enum.sum(Enum.map(bins, fn {_, _, c} -> c end))
      assert total == 50
    end
  end
end
