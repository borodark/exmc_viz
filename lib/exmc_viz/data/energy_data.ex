defmodule ExmcViz.Data.EnergyData do
  @moduledoc """
  Render-ready data for the energy diagnostic plot.

  The energy plot overlays two histograms to diagnose sampling problems:

  - **Marginal energy** (`energies`) — the Hamiltonian at the start of each
    leapfrog trajectory. Corresponds to the joint log-probability negated.
  - **Energy transition** (`transitions`) — absolute change in energy between
    consecutive steps. Large transitions suggest the sampler is struggling.

  When both distributions overlap well, the sampler is exploring efficiently.
  A heavy right tail on transitions indicates poor exploration (see Betancourt 2017).

  ## Fields

  - `energies` — per-step energy values (`-joint_logp`)
  - `transitions` — `[abs(E_n - E_{n-1})]` for consecutive steps
  - `hist_energy` — histogram of marginal energies
  - `hist_transition` — histogram of energy transitions
  - `max_count` — max bin count across both histograms (shared y-axis)
  """

  defstruct [
    :energies,
    :transitions,
    :hist_energy,
    :hist_transition,
    :max_count
  ]

  @type t :: %__MODULE__{
          energies: [float()],
          transitions: [float()],
          hist_energy: %{bins: [{float(), float(), non_neg_integer()}], max_count: non_neg_integer()},
          hist_transition: %{bins: [{float(), float(), non_neg_integer()}], max_count: non_neg_integer()},
          max_count: non_neg_integer()
        }
end
