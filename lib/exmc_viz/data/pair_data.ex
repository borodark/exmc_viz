defmodule ExmcViz.Data.PairData do
  @moduledoc """
  Render-ready data for a pair plot (corner plot).

  A pair plot is a k x k grid showing relationships between all variables:

  - **Diagonal** — marginal histogram of each variable
  - **Lower triangle** — scatter plot of pairwise samples
  - **Upper triangle** — Pearson correlation coefficient (r value)

  ## Fields

  - `var_names` — sorted list of variable names
  - `var_samples` — `%{name => [float()]}` per-variable sample lists
  - `correlations` — `%{{name_i, name_j} => float()}` pairwise Pearson r
  - `histograms` — `%{name => histogram_map}` per-variable histograms
  """

  defstruct [
    :var_names,
    :var_samples,
    :correlations,
    :histograms
  ]

  @type t :: %__MODULE__{
          var_names: [String.t()],
          var_samples: %{String.t() => [float()]},
          correlations: %{{String.t(), String.t()} => float()},
          histograms: %{
            String.t() => %{
              bins: [{float(), float(), non_neg_integer()}],
              max_count: non_neg_integer()
            }
          }
        }
end
