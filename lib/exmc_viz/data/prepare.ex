defmodule ExmcViz.Data.Prepare do
  @moduledoc """
  Converts MCMC trace/stats from Exmc samplers into render-ready data structs.

  This is the **only module that touches Nx tensors**. All downstream components
  and scenes receive plain Elixir lists, maps, and structs.

  ## Public API

  | Function               | Returns                | Used by                  |
  |------------------------|------------------------|--------------------------|
  | `from_trace/2`         | `[%VarData{}]`         | `ExmcViz.show/3`         |
  | `from_chains/1`        | `[%VarData{}]`         | `ExmcViz.show/3` (multi) |
  | `prepare_forest/1`     | `[%ForestData{}]`      | `ExmcViz.forest_plot/2`  |
  | `prepare_pairs/1`      | `%PairData{}`          | `ExmcViz.pair_plot/2`    |
  | `prepare_energy/1`     | `%EnergyData{}` / nil  | `ExmcViz.show/3`         |
  | `compute_hdi/3`        | `{lo, hi}`             | forest plot              |
  | `compute_histogram/2`  | histogram map          | all plots                |
  | `pearson_correlation/2` | float                 | pair plot                |
  """

  alias ExmcViz.Data.{VarData, ForestData, EnergyData, PairData}

  @max_acf_lag 40
  @default_bins 30

  @doc """
  Prepare a single-chain trace.

  `trace` is `%{name => Nx.t({n_samples, ...})}`.
  `stats` is the sampler stats map (optional). When provided, divergent indices
  are extracted from `stats.sample_stats` and attached to each `%VarData{}`.

  Returns a list of `%VarData{}`, one per variable, sorted by name.
  """
  def from_trace(trace, stats \\ nil) when is_map(trace) do
    div_indices = extract_divergent_indices(stats)

    trace
    |> Enum.map(fn {name, tensor} -> prepare_var(name, tensor, div_indices) end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Prepare a multi-chain trace.

  `traces` is a list of trace maps (one per chain).
  Returns a list of `%VarData{}` with per-chain data and R-hat.
  """
  def from_chains(traces) when is_list(traces) and length(traces) >= 2 do
    # Get variable names from the first chain
    names = traces |> hd() |> Map.keys() |> Enum.sort()

    Enum.map(names, fn name ->
      chain_tensors = Enum.map(traces, fn t -> Map.fetch!(t, name) end)
      chain_lists = Enum.map(chain_tensors, &Nx.to_flat_list/1)

      # Combine all chains for aggregate stats
      all_samples = List.flatten(chain_lists)
      n = length(all_samples)

      {mean, std} = mean_std(all_samples, n)
      quantiles = compute_quantiles(all_samples, n)
      ess = Exmc.Diagnostics.ess(all_samples)
      acf = Exmc.Diagnostics.autocorrelation(all_samples, min(@max_acf_lag, n - 1))
      histogram = compute_histogram(all_samples, @default_bins)
      rhat = Exmc.Diagnostics.rhat(chain_lists)

      %VarData{
        name: name,
        samples: all_samples,
        n_samples: n,
        mean: mean,
        std: std,
        quantiles: quantiles,
        ess: ess,
        histogram: histogram,
        acf: acf,
        chains: chain_lists,
        rhat: rhat
      }
    end)
  end

  # --- Private ---

  defp prepare_var(name, tensor, div_indices) do
    samples = Nx.to_flat_list(tensor)
    n = length(samples)

    {mean, std} = mean_std(samples, n)
    quantiles = compute_quantiles(samples, n)
    ess = Exmc.Diagnostics.ess(samples)
    acf = Exmc.Diagnostics.autocorrelation(samples, min(@max_acf_lag, n - 1))
    histogram = compute_histogram(samples, @default_bins)

    %VarData{
      name: name,
      samples: samples,
      n_samples: n,
      mean: mean,
      std: std,
      quantiles: quantiles,
      ess: ess,
      histogram: histogram,
      acf: acf,
      chains: nil,
      rhat: nil,
      divergent_indices: div_indices
    }
  end

  defp mean_std(values, n) when n > 0 do
    mean = Enum.sum(values) / n
    variance = Enum.sum(Enum.map(values, fn x -> (x - mean) * (x - mean) end)) / n
    std = :math.sqrt(max(variance, 0.0))
    {mean, std}
  end

  defp compute_quantiles(values, n) do
    sorted = Enum.sort(values)

    %{
      q5: quantile_at(sorted, n, 0.05),
      q25: quantile_at(sorted, n, 0.25),
      q50: quantile_at(sorted, n, 0.50),
      q75: quantile_at(sorted, n, 0.75),
      q95: quantile_at(sorted, n, 0.95)
    }
  end

  defp quantile_at(sorted, n, p) do
    h = (n - 1) * p
    lo = floor(h)
    hi = ceil(h)
    frac = h - lo
    lo_val = Enum.at(sorted, lo)
    hi_val = Enum.at(sorted, hi)
    lo_val + frac * (hi_val - lo_val)
  end

  @doc """
  Compute histogram bins from a list of floats.

  Returns `%{bins: [{left, right, count}, ...], max_count: integer}`.
  """
  def compute_histogram(values, num_bins) do
    {min_val, max_val} = Enum.min_max(values)

    # Pad range slightly if all values are identical
    {min_val, max_val} =
      if min_val == max_val do
        {min_val - 0.5, max_val + 0.5}
      else
        pad = (max_val - min_val) * 0.01
        {min_val - pad, max_val + pad}
      end

    bin_width = (max_val - min_val) / num_bins

    # Initialize counts
    counts = :array.new(num_bins, default: 0)

    counts =
      Enum.reduce(values, counts, fn v, acc ->
        idx = trunc((v - min_val) / bin_width)
        idx = min(idx, num_bins - 1)
        idx = max(idx, 0)
        :array.set(idx, :array.get(idx, acc) + 1, acc)
      end)

    bins =
      Enum.map(0..(num_bins - 1), fn i ->
        left = min_val + i * bin_width
        right = left + bin_width
        count = :array.get(i, counts)
        {left, right, count}
      end)

    max_count = bins |> Enum.map(fn {_, _, c} -> c end) |> Enum.max(fn -> 0 end)

    %{bins: bins, max_count: max_count}
  end

  @doc """
  Prepare forest plot data from a trace.

  Returns `[%ForestData{}]` sorted by name, with mean and 50%/94% HDI intervals.
  """
  def prepare_forest(trace) when is_map(trace) do
    trace
    |> Enum.map(fn {name, tensor} ->
      samples = Nx.to_flat_list(tensor)
      n = length(samples)
      sorted = Enum.sort(samples)
      mean = Enum.sum(samples) / n

      %ForestData{
        name: name,
        mean: mean,
        hdi_94: compute_hdi(sorted, n, 0.94),
        hdi_50: compute_hdi(sorted, n, 0.50)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Compute the narrowest interval containing `prob` mass from sorted samples.

  Returns `{lo, hi}`.
  """
  def compute_hdi(sorted, n, prob) when is_list(sorted) and n > 0 do
    interval_size = max(floor(prob * n), 1)

    if interval_size >= n do
      {hd(sorted), List.last(sorted)}
    else
      # Find the narrowest window of size interval_size
      sorted_arr = :array.from_list(sorted)

      {lo, hi, _width} =
        Enum.reduce(0..(n - interval_size - 1), {0, interval_size - 1, :infinity}, fn i,
                                                                                      {best_lo,
                                                                                       best_hi,
                                                                                       best_w} ->
          lo_val = :array.get(i, sorted_arr)
          hi_val = :array.get(i + interval_size - 1, sorted_arr)
          w = hi_val - lo_val

          if w < best_w do
            {i, i + interval_size - 1, w}
          else
            {best_lo, best_hi, best_w}
          end
        end)

      {:array.get(lo, sorted_arr), :array.get(hi, sorted_arr)}
    end
  end

  @doc """
  Prepare pair plot data from a trace.

  Returns `%PairData{}` with variable names sorted, per-variable samples,
  pairwise Pearson correlations, and per-variable histograms.
  """
  def prepare_pairs(trace) when is_map(trace) do
    names = trace |> Map.keys() |> Enum.sort()

    var_samples =
      Map.new(names, fn name ->
        {name, Nx.to_flat_list(trace[name])}
      end)

    histograms =
      Map.new(names, fn name ->
        {name, compute_histogram(var_samples[name], @default_bins)}
      end)

    # Compute pairwise correlations (lower triangle only, but store both directions)
    correlations =
      for i <- names, j <- names, i != j, into: %{} do
        {{i, j}, pearson_correlation(var_samples[i], var_samples[j])}
      end

    %PairData{
      var_names: names,
      var_samples: var_samples,
      correlations: correlations,
      histograms: histograms
    }
  end

  @doc """
  Compute Pearson correlation coefficient between two equal-length sample lists.
  """
  def pearson_correlation(xs, ys) do
    n = length(xs)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    {sum_xy, sum_xx, sum_yy} =
      Enum.zip(xs, ys)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y}, {sxy, sxx, syy} ->
        dx = x - mean_x
        dy = y - mean_y
        {sxy + dx * dy, sxx + dx * dx, syy + dy * dy}
      end)

    denom = :math.sqrt(sum_xx * sum_yy)

    if denom == 0.0 do
      0.0
    else
      sum_xy / denom
    end
  end

  @doc """
  Prepare energy diagnostic data from sampler stats.

  Extracts energies from `stats.sample_stats` and computes the energy transition
  distribution (absolute differences between consecutive energies).
  Returns `%EnergyData{}` or `nil` if stats lack energy information.
  """
  def prepare_energy(nil), do: nil

  def prepare_energy(%{sample_stats: sample_stats}) when is_list(sample_stats) do
    energies =
      sample_stats
      |> Enum.map(fn stat -> stat[:energy] end)
      |> Enum.filter(&is_number/1)

    if length(energies) < 2 do
      nil
    else
      transitions =
        energies
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> abs(b - a) end)

      hist_energy = compute_histogram(energies, @default_bins)
      hist_transition = compute_histogram(transitions, @default_bins)

      max_count = max(hist_energy.max_count, hist_transition.max_count)

      %EnergyData{
        energies: energies,
        transitions: transitions,
        hist_energy: hist_energy,
        hist_transition: hist_transition,
        max_count: max_count
      }
    end
  end

  def prepare_energy(_), do: nil

  @doc """
  Extract indices of divergent samples from stats.

  Returns a list of 0-based indices where `divergent == true`, or `nil` if
  stats is nil or has no sample_stats.
  """
  def extract_divergent_indices(nil), do: nil

  def extract_divergent_indices(%{sample_stats: sample_stats}) when is_list(sample_stats) do
    indices =
      sample_stats
      |> Enum.with_index()
      |> Enum.filter(fn {stat, _i} -> stat[:divergent] == true end)
      |> Enum.map(fn {_stat, i} -> i end)

    case indices do
      [] -> nil
      _ -> indices
    end
  end

  def extract_divergent_indices(_), do: nil

  @doc """
  Compute rank histograms for multi-chain diagnostics.

  Takes a list of traces (one per chain) and returns a list of `%RankData{}`
  structs, one per variable. Each contains per-chain rank histograms.
  Uniform rank distributions indicate good mixing.
  """
  def prepare_ranks(traces, num_bins \\ 20) when is_list(traces) and length(traces) > 0 do
    var_names = traces |> hd() |> Map.keys() |> Enum.sort()

    Enum.map(var_names, fn name ->
      # Pool all chains, compute ranks
      all_samples =
        Enum.flat_map(traces, fn trace ->
          Nx.to_flat_list(trace[name])
        end)

      n_total = length(all_samples)

      # Rank: position in sorted pooled samples
      indexed = Enum.with_index(all_samples)
      sorted = Enum.sort_by(indexed, &elem(&1, 0))

      ranks =
        Enum.reduce(Enum.with_index(sorted), %{}, fn {{_val, orig_idx}, rank}, acc ->
          Map.put(acc, orig_idx, rank)
        end)

      # Split ranks back by chain
      chain_sizes =
        Enum.map(traces, fn trace -> elem(Nx.shape(trace[name]), 0) end)

      {chain_ranks, _} =
        Enum.map_reduce(chain_sizes, 0, fn size, offset ->
          r = Enum.map(offset..(offset + size - 1), fn i -> Map.fetch!(ranks, i) end)
          {r, offset + size}
        end)

      # Histogram each chain's ranks
      bin_edges = Enum.map(0..num_bins, fn i -> i * n_total / num_bins end)

      rank_histograms =
        Enum.map(chain_ranks, fn chain_r ->
          Enum.map(0..(num_bins - 1), fn bin ->
            lo = Enum.at(bin_edges, bin)
            hi = Enum.at(bin_edges, bin + 1)
            Enum.count(chain_r, fn r -> r >= lo and r < hi end)
          end)
        end)

      %ExmcViz.Data.RankData{
        name: name,
        rank_histograms: rank_histograms,
        num_chains: length(traces),
        num_bins: num_bins
      }
    end)
  end

  @doc """
  Prepare posterior predictive check data.

  Takes observed data and predictive samples, returns a list of `%PPCData{}`
  structs with shared bin edges for overlay comparison.

  - `observed_data`: `%{obs_name => Nx.tensor or [float]}`
  - `predictive_trace`: `%{obs_name => Nx.tensor({n_samples, ...})}`
  """
  def prepare_ppc(observed_data, predictive_trace, num_bins \\ 30) do
    Enum.map(observed_data, fn {obs_name, obs_values} ->
      obs_list = if is_list(obs_values), do: obs_values, else: Nx.to_flat_list(obs_values)
      pred_samples = Map.fetch!(predictive_trace, obs_name)
      n_samples = elem(Nx.shape(pred_samples), 0)

      # Compute shared bin edges from combined data range
      pred_flat = Nx.to_flat_list(pred_samples)
      all_values = obs_list ++ pred_flat
      {lo, hi} = {Enum.min(all_values), Enum.max(all_values)}
      span = if hi == lo, do: 1.0, else: hi - lo
      lo = lo - 0.05 * span
      hi = hi + 0.05 * span
      bin_width = (hi - lo) / num_bins
      bin_edges = Enum.map(0..num_bins, fn i -> lo + i * bin_width end)

      # Histogram observed
      obs_hist = histogram_with_edges(obs_list, bin_edges, num_bins)

      # Histogram each predictive sample
      obs_size = length(obs_list)

      pred_hists =
        Enum.map(0..(n_samples - 1), fn i ->
          pred_row = Nx.to_flat_list(pred_samples[i])
          # Take only obs_size elements per sample row
          pred_row = Enum.take(pred_row, obs_size)
          histogram_with_edges(pred_row, bin_edges, num_bins)
        end)

      all_max =
        [Enum.max(obs_hist, fn -> 0 end) | Enum.map(pred_hists, &Enum.max(&1, fn -> 0 end))]
        |> Enum.max()

      %ExmcViz.Data.PPCData{
        obs_name: to_string(obs_name),
        observed_histogram: obs_hist,
        predictive_histograms: pred_hists,
        num_bins: num_bins,
        bin_edges: bin_edges,
        max_count: all_max
      }
    end)
  end

  defp histogram_with_edges(values, bin_edges, num_bins) do
    Enum.map(0..(num_bins - 1), fn i ->
      lo = Enum.at(bin_edges, i)
      hi = Enum.at(bin_edges, i + 1)
      Enum.count(values, fn v -> v >= lo and v < hi end)
    end)
  end
end
