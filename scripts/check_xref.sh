#!/usr/bin/env bash
# Fails when any module of the host stack is referenced, or when mix.exs lists a dependency outside
# jason, stream_data and credo.
set -u
cd "$(dirname "$0")/.."

status=0
for mod in Ash AshAgent AshPostgres AshPostgres.DataLayer Ecto Postgrex Ecto.Repo; do
  # xref reports nothing (or a warning on stderr) for a module that is not loaded; only stdout lines naming a file count.
  callers="$(mix xref callers "$mod" 2>/dev/null | grep -E '^[^ ].*:[0-9]+' || true)"
  if [ -n "$callers" ]; then
    echo "callers of $mod:"
    echo "$callers"
    status=1
  fi
done

deps="$(mix run --no-start -e 'IO.puts(Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.join(" "))' 2>/dev/null | tail -1)"
if [ "$deps" != "credo jason stream_data" ]; then
  echo "unexpected dependencies: $deps"
  status=1
fi

exit $status
