defmodule ExmcViz.MixProject do
  use Mix.Project

  def project do
    [
      app: :exmc_viz,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Native MCMC diagnostics visualization for Exmc",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["AGPL-3.0-only"],
      links: %{}
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
