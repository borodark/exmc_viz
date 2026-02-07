defmodule ExmcViz.Assets do
  use Scenic.Assets.Static,
    otp_app: :exmc_viz,
    sources: [
      {:scenic, Path.expand("../../../../scenic/assets", __DIR__)}
    ]
end
