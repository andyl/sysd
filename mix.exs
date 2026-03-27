defmodule Ziprel.MixProject do
  use Mix.Project

  @version "0.0.1"

  def project do
    [
      app: :ziprel,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      licenses: ["MIT"],
      docs: docs(),
      package: [
        name: "ziprel",
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/andyl/commit_hook",
          "Docs" => "https://hexdocs.pm/commit_hook"
        },
        files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE)
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [{"README.md", title: "Overview"}],
      source_url: "https://github.com/andyl/ziprel",
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:sshex, "~> 2.0"},
      {:commit_hook, "~> 0.4"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:git_ops, "~> 2.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

end
