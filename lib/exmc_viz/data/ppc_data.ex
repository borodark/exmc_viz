defmodule ExmcViz.Data.PPCData do
  @moduledoc "Data struct for posterior predictive check visualization."
  defstruct [
    :obs_name,
    :observed_histogram,
    :predictive_histograms,
    :num_bins,
    :bin_edges,
    :max_count
  ]

  # observed_histogram: [count, ...]
  # predictive_histograms: [[count, ...], ...] — one per posterior sample (subset)
end
