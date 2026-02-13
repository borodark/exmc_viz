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
      {:exmc, git: "https://github.com/borodark/exmc.git", tag: "β"},
      {:scenic, git: "https://github.com/ScenicFramework/scenic.git", tag: "v0.11.1", override: true},
      {:scenic_driver_local, git: "https://github.com/ScenicFramework/scenic_driver_local.git", tag: "v0.11.0"},
      {:nimble_options, "~> 0.3.4 or ~> 0.4.0 or ~> 0.5.0 or ~> 1.1"}
    ]
  end
end
