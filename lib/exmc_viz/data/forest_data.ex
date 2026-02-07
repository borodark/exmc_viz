defmodule ExmcViz.Data.ForestData do
  @moduledoc """
  Render-ready data for a single variable in a forest plot.

  Each variable is represented as a horizontal interval chart:
  a thin line for the 94% Highest Density Interval, a thick line for the
  50% HDI, and a dot at the posterior mean.

  ## Fields

  - `name` — variable identifier
  - `mean` — posterior mean
  - `hdi_94` — `{lo, hi}` bounds of the 94% HDI (narrowest interval)
  - `hdi_50` — `{lo, hi}` bounds of the 50% HDI
  """

  defstruct [
    :name,
    :mean,
    :hdi_94,
    :hdi_50
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          mean: float(),
          hdi_94: {float(), float()},
          hdi_50: {float(), float()}
        }
end
