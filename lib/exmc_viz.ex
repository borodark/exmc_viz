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

  @default_width 2160
  @default_height 3840

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

  - `:width` — window width (default: 2160)
  - `:title` — window title (default: "MCMC Trace Diagnostics")
  """
  def show(trace_or_traces, stats_or_stats_list \\ nil, opts \\ []) do
    var_data_list = prepare_data(trace_or_traces, stats_or_stats_list)
    energy_data = prepare_energy(stats_or_stats_list)

    width = opts[:width] || @default_width
    title = opts[:title] || "MCMC Trace Diagnostics"
    height = opts[:height] || @default_height

    scene_data = {var_data_list, energy_data}

    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.Dashboard, scene_data},
      drivers: [driver_config(:local, title)]
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

    width = opts[:width] || 1600
    title = opts[:title] || "Forest Plot"
    n_vars = length(forest_data_list)
    height = max(600, 120 + n_vars * 120 + 80)

    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_forest_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.Forest, forest_data_list},
      drivers: [driver_config(:local_forest, title)]
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
    default_size = max(800, k * 500 + 160)
    width = opts[:width] || default_size
    height = width
    title = opts[:title] || "Pair Plot"

    ensure_scenic_started()

    viewport_config = [
      name: :exmc_viz_pair_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.PairPlot, pair_data},
      drivers: [driver_config(:local_pair, title)]
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
    height = Keyword.get(opts, :height, @default_height)

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
      drivers: [driver_config(:local_live, title)]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  @doc """
  Start a live dashboard in external mode for multi-chain streaming.

  Opens a Scenic window but does NOT start a sampler task. Instead, returns
  the coordinator PID so external processes (e.g. distributed peer nodes)
  can send `{:exmc_sample, i, point_map, step_stat}` and `{:exmc_done, total}`
  messages directly.

  ## Options

  - `:width` — window width (default: 2160)
  - `:height` — window height (default: 3840)
  - `:title` — window title (default: "MCMC Live Sampling")
  - `:num_samples` — total expected samples across all chains (default: 1000)
  """
  def stream_external(var_names, opts \\ []) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    title = Keyword.get(opts, :title, "MCMC Live Sampling")
    num_samples = Keyword.get(opts, :num_samples, 1000)

    ensure_scenic_started()

    scene_opts = %{
      ir: nil,
      num_samples: num_samples,
      var_names: var_names
    }

    viewport_config = [
      name: :exmc_viz_live_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.LiveDashboard, scene_opts},
      drivers: [driver_config(:local_live, title)]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    # Poll for coordinator PID (set by LiveDashboard.init via persistent_term)
    coordinator_pid = poll_coordinator(50, 100)
    {:ok, coordinator_pid}
  end

  defp poll_coordinator(0, _interval), do: raise("ExmcViz coordinator did not start in time")

  defp poll_coordinator(retries, interval) do
    case :persistent_term.get(:exmc_viz_coordinator, nil) do
      nil ->
        Process.sleep(interval)
        poll_coordinator(retries - 1, interval)

      pid ->
        pid
    end
  end

  @doc """
  Show a CFD observability dashboard over Scenic Remote.

  Requires a Scenic remote renderer (native OpenGL window) to be running.

  ## Options

  - `:width` — viewport width (default: 1600)
  - `:height` — viewport height (default: 900)
  - `:title` — window title (default: "CFD Observability")
  - `:host` — remote renderer host (default: "127.0.0.1")
  - `:port` — remote renderer TCP port (default: 4000)
  - `:metrics_port` — TCP port to ingest metrics (default: 4100)
  """
  def cfd_dashboard(opts \\ []) do
    width = Keyword.get(opts, :width, 1600)
    height = Keyword.get(opts, :height, 900)
    title = Keyword.get(opts, :title, "CFD Observability")

    ensure_scenic_started()
    ensure_metrics_started(opts)

    viewport_config = [
      name: :exmc_viz_cfd_viewport,
      size: {width, height},
      default_scene: {ExmcViz.Scene.CfdDashboard, %{}},
      drivers: [driver_config(:remote_cfd, title, opts)]
    ]

    {:ok, _viewport} = Scenic.ViewPort.start(viewport_config)

    :ok
  end

  @doc """
  Start the CFD terminal dashboard (orange-on-black, 8 panels).

  Uses the same metrics bus as the Scenic dashboard.
  """
  def cfd_terminal do
    ensure_metrics_started([])
    ExmcViz.Cfd.Terminal.start()
    :ok
  end

  defp ensure_scenic_started do
    case Process.whereis(:scenic) do
      nil -> Scenic.start_link([])
      _pid -> :ok
    end
  end

  defp driver_config(name, title, opts \\ []) do
    if opts[:remote] || name == :remote_cfd do
      host = opts[:host] || "127.0.0.1"
      port = opts[:port] || 4000

      [
        module: ScenicDriverRemote,
        transport: ScenicDriverRemote.Transport.Tcp,
        host: host,
        port: port,
        reconnect_interval: 1000
      ]
    else
      [
        module: Scenic.Driver.Local,
        name: name,
        antialias: false,
        window: [title: title, resizeable: false],
        on_close: :stop_driver
      ]
    end
  end

  defp ensure_metrics_started(opts) do
    unless Process.whereis(ExmcViz.Cfd.Metrics) do
      {:ok, _} = ExmcViz.Cfd.Metrics.start_link([])
    end

    metrics_port = opts[:metrics_port] || 4100

    unless Process.whereis(ExmcViz.Cfd.MetricsSocket) do
      {:ok, _} = ExmcViz.Cfd.MetricsSocket.start_link(port: metrics_port)
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
