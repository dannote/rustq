defmodule RustQ.Rustler.HelperSelectionTest do
  use ExUnit.Case, async: true

  alias RustQ.Rustler.HelperSelection

  test "uses default names when include is omitted" do
    assert HelperSelection.names([], [:a, :b]) == [:a, :b]
  end

  test "supports :all include and excludes selected helpers" do
    assert HelperSelection.names([include: :all, exclude: [:b]], [:a, :b, :c]) == [:a, :c]
  end

  test "supports explicit include lists" do
    assert HelperSelection.names([include: [:b, :c], exclude: [:c]], [:a, :b, :c]) == [:b]
  end
end
