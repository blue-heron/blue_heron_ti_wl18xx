defmodule BlueHeronTiWl18xx.MixProject do
  use Mix.Project

  def project do
    [
      app: :blue_heron_ti_wl18xx,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:blue_heron_transport_uart, github: "blue-heron/blue_heron_transport_uart", branch: "wilink8"},
      {:circuits_gpio, "~> 1.0"}
    ]
  end
end
