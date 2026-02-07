# ExmcViz Phase III Demo
#
# Run from exmc_viz/:
#   mix run demo.exs
#
# Opens all five visualization windows in sequence.
# Live streaming goes first so you can watch it fill in for ~5 minutes.

alias Exmc.Builder
alias Exmc.Dist.{Normal, HalfNormal}

# ====================================================================
# --- 1. LIVE STREAMING (first — the main event, ~5 minutes) ---
# ====================================================================

IO.puts("Building 3-variable model for live streaming...")

ir_live =
  Builder.new_ir()
  |> Builder.rv("mu", Normal, %{mu: Nx.tensor(0.0), sigma: Nx.tensor(5.0)})
  |> Builder.rv("sigma", HalfNormal, %{sigma: Nx.tensor(2.0)})
  |> Builder.rv("x", Normal, %{mu: "mu", sigma: "sigma"})
  |> Builder.obs("x_obs", "x",
    Nx.tensor([2.1, 1.8, 2.5, 2.0, 1.9, 2.3, 2.2, 1.7, 2.4, 2.6,
               1.6, 2.8, 2.1, 1.5, 2.7, 2.0, 1.9, 2.4, 2.2, 2.3])
  )

IO.puts("""

=== LIVE STREAMING ===
Watch the trace plots, histograms, and ACF fill in as the sampler runs.
Title bar shows progress: (N / 3000)
This will take about 5 minutes on BinaryBackend.
""")

ExmcViz.stream(ir_live, %{"mu" => 2.0, "sigma" => 1.0},
  num_samples: 3000,
  num_warmup: 500,
  title: "Demo: Live Streaming (3000 samples)"
)

IO.gets("Press Enter after sampling completes and you've closed the window...")

# ====================================================================
# --- 2. STATIC DASHBOARD (with energy row + divergence markers) ---
# ====================================================================

IO.puts("Building simple model for static dashboard...")

ir =
  Builder.new_ir()
  |> Builder.rv("mu", Normal, %{mu: Nx.tensor(0.0), sigma: Nx.tensor(5.0)})
  |> Builder.rv("x", Normal, %{mu: "mu", sigma: Nx.tensor(1.0)})
  |> Builder.obs("x_obs", "x",
    Nx.tensor([2.1, 1.8, 2.5, 2.0, 1.9, 2.3, 2.2, 1.7, 2.4, 2.6])
  )

IO.puts("Sampling (200 draws)...")
{trace, stats} = Exmc.NUTS.Sampler.sample(ir, %{}, num_samples: 200, num_warmup: 200)

IO.puts("Posterior mean(mu) = #{Float.round(Nx.to_number(Nx.mean(trace["mu"])), 3)}")
IO.puts("Divergences: #{stats.divergences}")
IO.puts("Energy captured: #{stats.sample_stats |> hd() |> Map.has_key?(:energy)}")

IO.puts("\nOpening dashboard (trace + histogram + ACF + summary + energy row)...")
ExmcViz.show(trace, stats, title: "Demo: Dashboard + Energy")
Process.sleep(500)
IO.gets("Press Enter after closing the window...")

# ====================================================================
# --- 3 & 4. FOREST PLOT + PAIR PLOT (shared 3-variable model) ---
# ====================================================================

IO.puts("Building 3-variable model for forest + pair plots...")

ir2 =
  Builder.new_ir()
  |> Builder.rv("alpha", Normal, %{mu: Nx.tensor(0.0), sigma: Nx.tensor(2.0)})
  |> Builder.rv("beta", Normal, %{mu: Nx.tensor(3.0), sigma: Nx.tensor(1.0)})
  |> Builder.rv("sigma", HalfNormal, %{sigma: Nx.tensor(1.0)})
  |> Builder.rv("y_lat", Normal, %{mu: "alpha", sigma: "sigma"})
  |> Builder.obs("y_obs", "y_lat",
    Nx.tensor([0.5, -0.2, 0.8, 0.1, 0.3])
  )

IO.puts("Sampling (300 draws)...")
{trace2, _stats2} = Exmc.NUTS.Sampler.sample(ir2,
  %{"alpha" => 0.0, "beta" => 3.0, "sigma" => 1.0},
  num_samples: 300, num_warmup: 200
)

IO.puts("Opening forest plot (3 variables: alpha, beta, sigma)...")
ExmcViz.forest_plot(trace2, title: "Demo: Forest Plot (3 vars)")
Process.sleep(500)
IO.gets("Press Enter after closing the window...")

IO.puts("Opening pair plot (3x3 grid: hist / scatter / correlation)...")
ExmcViz.pair_plot(trace2, title: "Demo: Pair Plot (3 vars)")
Process.sleep(500)
IO.gets("Press Enter after closing the window...")

IO.puts("\nDone! All features demonstrated.")
