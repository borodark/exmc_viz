defmodule ExmcViz do
  @moduledoc """
  ArviZ-style MCMC diagnostics visualization for Exmc.

  Renders native Scenic windows with amber-on-black OLED theme.
  All Nx tensor work happens in `ExmcViz.Data.Prepare`; components
  receive only plain Elixir data.

  ## Visualization types

  | Function        | What it shows                                        |
  |-----------------|------------------------------------------------------|
  | `show/3`        | Dashboard: trace, histogram, ACF, summary per var    |
  | `forest_plot/2` | HDI intervals (50% + 94%) with mean dots             |
  | `pair_plot/2`   | k x k grid: hist diagonal, scatter lower, corr upper |
  | `stream/3`      | Live-updating dashboard during sampling              |

  ## Quick start

      # Static dashboard (single chain)
      {trace, stats} = Exmc.NUTS.Sampler.sample(ir, %{}, num_samples: 1000)
      ExmcViz.show(trace, stats)

      # Static dashboard (multi-chain, shows R-hat + per-chain colors)
      {traces, stats_list} = Exmc.NUTS.Sampler.sample_chains(ir, 4)
      ExmcViz.show(traces, stats_list)

      # Forest plot
      ExmcViz.forest_plot(trace)

      # Pair plot (corner plot)
      ExmcViz.pair_plot(trace)

      # Live streaming (watch plots fill in as sampler runs)
      ExmcViz.stream(ir, %{}, num_samples: 500)
  """

  alias ExmcViz.Data.Prepare

  @default_width 1280
  @row_height 200
  @title_height 40

  @doc """
  Show MCMC diagnostics in a native window.

  One row per variable with four panels: trace plot, histogram, ACF, and
  summary statistics. When `stats` is provided, divergent samples appear as
  red dots on trace plots, and an energy diagnostic row is appended at the
  bottom (if the sampler captured energy).

  ## Single chain

      ExmcViz.show(trace, stats)

  Where `trace` is `%{name => Nx.tensor}` and `stats` is the sampler stats map.

  ## Multi-chain

      ExmcViz.show(traces, stats_list)

  Where `traces` is a list of trace maps and `stats_list` is a list of stats.
  Multi-chain mode shows per-chain line colors on traces and adds R-hat to
  the summary panel.

  ## Options

  - `:width` — window width (default: 1280)
  - `:title` — window title (default: "MCMC Trace Diagnostics")
  """
  def show(trace_or_traces, stats_or_stats_list \\ nil, opts \\ []) do
    var_data_list = prepare_data(trace_or_traces, stats_or_stats_list)
    energy_data = prepare_energy(stats_or_stats_list)

    width = opts[:width] || @default_width
    title = opts[:title] || "MCMC Trace Diagnostics"
    n_vars = length(var_data_list)
    energy_extra = if energy_data, do: @row_height, else: 0
    height = max(600, @title_height + n_vars * @row_height + energy_extra + 20)

    scene_data = {var_data_list, energy_data}

    # Ensure Scenic supervisor is running
    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.Dashboard, scene_data},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :local,
          window: [title: title, resizeable: false],
          on_close: :stop_driver
        ]
      ]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  @doc """
  Show a forest plot in a separate native window.

  Displays HDI intervals (50% thick, 94% thin) and mean dot for each variable.

  ## Options

  - `:width` — window width (default: 800)
  - `:title` — window title (default: "Forest Plot")
  """
  def forest_plot(trace, opts \\ []) when is_map(trace) do
    forest_data_list = Prepare.prepare_forest(trace)

    width = opts[:width] || 800
    title = opts[:title] || "Forest Plot"
    n_vars = length(forest_data_list)
    height = max(300, 60 + n_vars * 40 + 40)

    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_forest_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.Forest, forest_data_list},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :local_forest,
          window: [title: title, resizeable: false],
          on_close: :stop_driver
        ]
      ]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  @doc """
  Show a pair plot (corner plot) in a separate native window.

  k x k grid: diagonal = histogram, lower triangle = scatter, upper = correlation.

  ## Options

  - `:width` — window width (default: auto-sized to k)
  - `:title` — window title (default: "Pair Plot")
  """
  def pair_plot(trace, opts \\ []) when is_map(trace) do
    pair_data = Prepare.prepare_pairs(trace)

    k = length(pair_data.var_names)
    default_size = max(400, k * 220 + 80)
    width = opts[:width] || default_size
    height = width
    title = opts[:title] || "Pair Plot"

    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_pair_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.PairPlot, pair_data},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :local_pair,
          window: [title: title, resizeable: false],
          on_close: :stop_driver
        ]
      ]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  @doc """
  Stream MCMC sampling with live visualization.

  Opens a Scenic window that updates in real-time as the sampler draws
  samples. The title bar shows `"MCMC Live Sampling (N / total)"` during
  sampling and switches to `"(complete)"` when done.

  Internally starts a `StreamCoordinator` that buffers 10 samples before
  flushing to the display, keeping the UI responsive while the sampler
  runs at full speed in a background task.

  ## Options

  - `:width` — window width (default: 1280)
  - `:title` — window title (default: "MCMC Live Sampling")
  - `:num_samples` — number of post-warmup samples (default: 1000)
  - `:num_warmup` — warmup iterations (default: 1000)
  - `:seed` — PRNG seed (default: 0)
  - `:target_accept` — target acceptance probability (default: 0.8)
  """
  def stream(ir, init_values \\ %{}, opts \\ []) do
    width = Keyword.get(opts, :width, @default_width)
    title = Keyword.get(opts, :title, "MCMC Live Sampling")
    num_samples = Keyword.get(opts, :num_samples, 1000)

    # Get variable names from IR point map
    pm = Exmc.PointMap.build(ir)
    var_names = Enum.map(pm.entries, & &1.id)
    n_vars = length(var_names)
    height = max(600, @title_height + n_vars * @row_height + 20)

    ensure_scenic_started()

    scene_opts = %{
      ir: ir,
      init_values: init_values,
      sampler_opts: Keyword.drop(opts, [:width, :title]),
      num_samples: num_samples,
      var_names: var_names
    }

    viewport_config = [
      name: :exmc_viz_live_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.LiveDashboard, scene_opts},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :local_live,
          window: [title: title, resizeable: false],
          on_close: :stop_driver
        ]
      ]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  defp ensure_scenic_started do
    case Process.whereis(:scenic) do
      nil -> Scenic.start_link([])
      _pid -> :ok
    end
  end

  defp prepare_data(traces, _stats) when is_list(traces) do
    Prepare.from_chains(traces)
  end

  defp prepare_data(trace, stats) when is_map(trace) do
    Prepare.from_trace(trace, stats)
  end

  defp prepare_energy(stats) when is_map(stats), do: Prepare.prepare_energy(stats)
  defp prepare_energy(_), do: nil
end
