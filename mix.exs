defmodule Sysd.MixProject do
  use Mix.Project

  @version "0.4.1"

  def project do
    [
      app: :sysd,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      licenses: ["MIT"],
      docs: docs(),
      package: [
        name: "sysd",
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/andyl/sysd",
          "Docs" => "https://hexdocs.pm/sysd"
        },
        files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
      ],
      escript: [main_module: Sysd.CLI, name: "sysd"],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh, :public_key]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [{"README.md", title: "Overview"}],
      source_url: "https://github.com/andyl/sysd",
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:optimus, "~> 0.5"},
      {:sshex, "~> 2.0"},
      {:yaml_elixir, "~> 2.11"},
      {:commit_hook, "~> 0.4"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:git_ops, "~> 2.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end
end
