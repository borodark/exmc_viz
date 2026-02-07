# ExmcViz

**Native MCMC diagnostics for Exmc.** ArviZ-style visualization rendered through Scenic on a true-black OLED palette -- trace plots, histograms, ACF, pair plots, forest plots, energy diagnostics, and live streaming that updates as the sampler runs.

![Live Streaming Dashboard](assets/live_streaming.png)

## Why Native?

Python's ArviZ renders to Matplotlib. That means a Python runtime, a GUI toolkit, and a round-trip through PNG or SVG every time you want to look at your chains. Jupyter notebooks cache these as static images -- zoom in on a suspicious region and you get pixels, not data.

ExmcViz renders directly through Scenic's OpenGL pipeline. Every frame is a live scene graph: resize the window, the plots re-render at native resolution. The same rendering path drives static dashboards, interactive pair plots, and real-time streaming from an active sampler -- no file I/O, no image encoding, no external processes.

The amber-on-black palette is not decorative. True black (`{0,0,0}`) means zero power on OLED panels. The warm spectrum -- amber, gold, burnt orange -- preserves night-adapted vision during long sampling sessions and provides enough hue variation for ten chains without reaching for blue or green.

## Visualization Types

| Function | What it shows | Window |
|----------|--------------|--------|
| `show/3` | Dashboard: trace, histogram, ACF, summary per variable | Portrait 4K |
| `forest_plot/2` | HDI intervals (50% + 94%) with posterior means | Sized to variable count |
| `pair_plot/2` | k x k grid: histogram diagonal, scatter lower, correlation upper | Square, scaled to k |
| `stream/3` | Live-updating dashboard during active sampling | Portrait 4K |

## Quick Start

```elixir
# After sampling with Exmc
{trace, stats} = Exmc.NUTS.Sampler.sample(ir, init, num_samples: 1000)

# Static dashboard — one row per variable
ExmcViz.show(trace, stats)

# Multi-chain overlay (per-chain colors, R-hat in summary)
{traces, stats_list} = Exmc.NUTS.Sampler.sample_chains(ir, 4, init_values: init)
ExmcViz.show(traces, stats_list)

# Forest plot — HDI intervals at a glance
ExmcViz.forest_plot(trace)

# Pair plot — posterior correlations
ExmcViz.pair_plot(trace)

# Live streaming — watch the sampler work
ExmcViz.stream(ir, init, num_samples: 500)
```

## Architecture

```
ExmcViz.show(trace, stats)
  │
  ├─ Data.Prepare          Nx tensors → plain Elixir lists/maps
  │   ├─ from_trace()      Single chain: samples, ACF, histogram, ESS
  │   ├─ from_chains()     Multi-chain: merge + R-hat
  │   ├─ prepare_energy()  Energy + transition histograms
  │   ├─ prepare_forest()  HDI intervals via narrowest-window algorithm
  │   └─ prepare_pairs()   Pearson correlations, per-variable samples
  │
  ├─ Scene.Dashboard       Scenic scene: lays out components vertically
  │   ├─ TracePlot         Time series with optional divergence markers
  │   ├─ Histogram         Marginal distribution with vertical bin bars
  │   ├─ AcfPlot           Autocorrelation with significance band
  │   ├─ SummaryPanel      Mean, std, quantiles, ESS, R-hat
  │   └─ EnergyPlot        Overlaid marginal + transition energy histograms
  │
  ├─ Scene.Forest          Horizontal HDI bars + mean dots
  │   └─ ForestPlot        Thin line (94%), thick line (50%), white dot
  │
  ├─ Scene.PairPlot        k × k grid scene
  │   ├─ Histogram         Diagonal: marginal distributions
  │   ├─ ScatterPlot       Lower triangle: pairwise samples (≤500 pts)
  │   └─ CorrelationCell   Upper triangle: Pearson r with scaled font
  │
  └─ Scene.LiveDashboard   Same layout as Dashboard, rebuilt on each batch
      └─ Stream.Coordinator   GenServer buffering 10 samples per flush
```

All Nx tensor computation happens in `Data.Prepare`. Components receive plain Elixir lists and floats. This boundary means Scenic never touches Nx, and Nx never touches the scene graph.

## Dashboard Layout

Portrait orientation, optimized for vertical 4K displays (2160 x 3840):

```
┌─────────────────────────┐
│  MCMC Trace Diagnostics │  title
├─────────────────────────┤
│  ▬▬▬▬▬▬▬▬ trace ▬▬▬▬▬▬ │  full width, 300px
├──────────────┬──────────┤
│  histogram   │   ACF    │  55% / 45%, 250px
├──────────────┴──────────┤
│  mean  std  q5 ... ESS  │  summary, 100px
├─────────────────────────┤
│  ▬▬▬▬▬▬▬▬ trace ▬▬▬▬▬▬ │  next variable...
│  ...                    │
├─────────────────────────┤
│  Energy (marginal+trans)│  energy row, 300px
└─────────────────────────┘
```

## Live Streaming

`ExmcViz.stream/3` connects the sampler directly to the visualization:

1. Opens a Scenic viewport with `LiveDashboard` scene
2. Starts a `StreamCoordinator` GenServer
3. Launches the sampler in a background `Task`
4. Sampler sends `{:exmc_sample, i, point_map, step_stat}` per draw
5. Coordinator buffers 10 samples, then flushes accumulated trace to the scene
6. Scene rebuilds the full graph with updated data
7. Title bar shows progress: `"MCMC Live Sampling (150 / 500)"`

The sampler runs at full speed in its own process. The coordinator's 10-sample buffer keeps Scenic responsive without throttling the sampler.

## Color Palette

| Role | RGB | Use |
|------|-----|-----|
| Background | `{0, 0, 0}` | True black (zero OLED power) |
| Default line | `{255, 176, 0}` | Amber trace lines, histogram bars |
| Divergence | `{255, 50, 50}` | Red dots on divergent samples |
| Energy transition | `{80, 140, 220}` | Blue overlay on energy plot |
| Forest HDI thin | `{140, 110, 60}` | 94% interval (dim amber) |
| Forest HDI thick | `{255, 176, 0}` | 50% interval (bright amber) |
| Forest mean | `{255, 255, 255}` | White dot |
| Text | `{255, 200, 120}` | Labels, titles |

Ten chain colors cycle through the warm spectrum: amber, deep orange, gold, burnt orange, tangerine, dark gold, light amber, rust, pale gold, bronze.

## Dependencies

```elixir
{:exmc, path: "../exmc"},
{:scenic, path: "../../scenic", override: true},
{:scenic_driver_local, git: "https://github.com/ScenicFramework/scenic_driver_local.git"}
```

Scenic 0.12.0-rc.0 via local path. The `override: true` is required because scenic_driver_local declares `scenic ~> 0.12` and the local path dep needs to satisfy it.

## Test Suite

34 tests covering data preparation (histograms, ACF, ESS, HDI, correlations, energy), linear scaling, and multi-chain merge logic. All visualization is tested through the `Data.Prepare` layer -- components are pure Scenic graph builders with no state to test.

![Pair Plot](assets/pair_plot_4k.png)

## License

[GNU Affero General Public License v2.0](./LICENSE)

P.S.

```
❯ In a latin _Documenting important things_ would be what?                                                      
                                                           
● Res gestae notatu dignae -- "things done worthy of noting"                                                    
                                                           
  Or more concisely for a section header:                                                                       
   
  - Notanda -- "things to be noted"                                                                             
  - Memoranda -- "things to be remembered" (origin of the English word)
  - Acta notabilia -- "notable proceedings"

  For a DECISIONS.md-style document, Memoranda fits best -- it literally means "things that must be remembered,"
   which is exactly what architectural decision records are.
```
