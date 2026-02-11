defmodule ExmcViz.Draw.Colors do
  @moduledoc """
  OLED-optimized amber color palette for MCMC visualization.

  True black everywhere. Amber/gold accents.
  """

  # True black everywhere
  @bg {0, 0, 0}
  @panel_bg {0, 0, 0}
  @axis {50, 45, 30}
  @grid {25, 22, 15}
  @text {255, 200, 120}
  @text_dim {140, 110, 60}

  # Amber multi-chain palette (warm spectrum)
  @palette [
    # amber
    {255, 176, 0},
    # deep orange
    {255, 120, 0},
    # gold
    {255, 220, 80},
    # burnt orange
    {200, 100, 0},
    # tangerine
    {255, 150, 50},
    # dark gold
    {180, 140, 0},
    # light amber
    {255, 200, 100},
    # rust
    {220, 80, 0},
    # pale gold
    {255, 240, 150},
    # bronze
    {160, 120, 40}
  ]

  def bg, do: @bg
  def panel_bg, do: @panel_bg
  def axis, do: @axis
  def grid, do: @grid
  def text, do: @text
  def text_dim, do: @text_dim

  def chain_color(index) when is_integer(index) do
    Enum.at(@palette, rem(index, 10))
  end

  def default_line, do: {255, 176, 0}
  def hist_fill, do: {255, 160, 0}
  def acf_bar, do: {255, 176, 0}
  def sig_band, do: {60, 50, 25}
  def divergence, do: {255, 50, 50}

  # Energy plot
  def energy_marginal, do: {255, 176, 0}
  def energy_transition, do: {80, 140, 220}

  # Forest plot
  def forest_thin, do: {140, 110, 60}
  def forest_thick, do: {255, 176, 0}
  def forest_dot, do: {255, 255, 255}
end
