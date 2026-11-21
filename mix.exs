defmodule AshProvenance.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lukegalea/ash_provenance"

  def project do
    [
      app: :ash_provenance,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Plain-data contract for explaining where a value came from: addresses, PROV-DM steps, typed gaps and a PROV-O JSON-LD export.",
      package: package(),
      source_url: @source_url
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Source" => @source_url},
      files: ~w(lib mix.exs README.md usage-rules.md CHANGELOG.md NOTICE LICENSE .formatter.exs)
    ]
  end
end
