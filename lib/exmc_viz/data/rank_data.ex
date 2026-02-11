defmodule ExmcViz.Data.RankData do
  @moduledoc "Data struct for rank plot visualization."
  defstruct [:name, :rank_histograms, :num_chains, :num_bins]
  # rank_histograms: [[count, ...], ...] — one histogram per chain
end
