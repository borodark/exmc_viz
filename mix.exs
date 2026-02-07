defmodule ExmcViz.MixProject do
  use Mix.Project

  def project do
    [
      app: :exmc_viz,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exmc, path: "../exmc"},
      {:scenic, path: "../../scenic", override: true},
      {:scenic_driver_local, git: "https://github.com/ScenicFramework/scenic_driver_local.git"}
    ]
  end
end
