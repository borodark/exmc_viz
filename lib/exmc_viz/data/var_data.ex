defmodule ExmcViz.Data.VarData do
  @moduledoc """
  Render-ready data for a single MCMC variable.

  All Nx tensor work is done in `ExmcViz.Data.Prepare` before constructing
  this struct. Components receive only plain Elixir data.

  ## Fields

  - `name` — variable identifier (e.g. `"mu"`)
  - `samples` — flattened list of posterior draws
  - `n_samples` — total sample count
  - `mean`, `std` — posterior mean and standard deviation
  - `quantiles` — map with keys `:q5`, `:q25`, `:q50`, `:q75`, `:q95`
  - `ess` — effective sample size (via `Exmc.Diagnostics`)
  - `histogram` — `%{bins: [{left, right, count}], max_count: int}`
  - `acf` — autocorrelation values up to lag 40
  - `chains` — per-chain sample lists (multi-chain only, else `nil`)
  - `rhat` — Gelman-Rubin convergence diagnostic (multi-chain only, else `nil`)
  - `divergent_indices` — 0-based indices where NUTS diverged (else `nil`)
  """

  defstruct [
    :name,
    :samples,
    :n_samples,
    :mean,
    :std,
    :quantiles,
    :ess,
    :histogram,
    :acf,
    :chains,
    :rhat,
    :divergent_indices
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          samples: [float()],
          n_samples: non_neg_integer(),
          mean: float(),
          std: float(),
          quantiles: %{q5: float(), q25: float(), q50: float(), q75: float(), q95: float()},
          ess: float(),
          histogram: %{bins: [{float(), float(), non_neg_integer()}], max_count: non_neg_integer()},
          acf: [float()],
          chains: [[float()]] | nil,
          rhat: float() | nil,
          divergent_indices: [non_neg_integer()] | nil
        }
end
