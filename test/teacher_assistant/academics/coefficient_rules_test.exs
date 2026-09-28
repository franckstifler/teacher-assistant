defmodule TeacherAssistant.Academics.CoefficientRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.CoefficientRules

  @blank {"maths", :francophone, "2nde", nil}
  @serie_c {"maths", :francophone, "2nde", "C"}
  @cells %{@blank => Decimal.new(4), @serie_c => Decimal.new(5)}
  @class_c %{subject_id: "maths", subsystem: :francophone, level: "2nde", serie: "C", class_label: "2nde C"}
  @class_a %{subject_id: "maths", subsystem: :francophone, level: "2nde", serie: "A4", class_label: "2nde A"}

  defp errors(result) do
    assert {:error, {:invalid, errors}} = result
    errors
  end

  test "resolve prefers the série cell, then the blank cell" do
    assert CoefficientRules.resolve(@cells, @class_c) == @serie_c
    assert CoefficientRules.resolve(@cells, @class_a) == @blank
    assert CoefficientRules.resolve(%{}, @class_a) == nil
  end

  test "valid changes pass" do
    assert :ok =
             CoefficientRules.validate(@cells, %{@blank => Decimal.new(3)}, %{"maths" => :g2_sciences}, [@class_a, @class_c])
  end

  test "an unparseable coefficient is reported on its cell" do
    errs = errors(CoefficientRules.validate(@cells, %{@blank => :invalid}, %{}, []))
    assert errs[@blank] == [:invalid_coefficient]
  end

  test "clearing a série cell is allowed while the blank cell covers the class" do
    assert :ok = CoefficientRules.validate(@cells, %{@serie_c => nil}, %{}, [@class_c])
  end

  test "clearing the cell a class resolves to, with nothing behind it, names the classes" do
    errs = errors(CoefficientRules.validate(@cells, %{@blank => nil}, %{}, [@class_a, @class_c]))
    assert errs[@blank] == [{:in_use, ["2nde A"]}]

    errs = errors(CoefficientRules.validate(@cells, %{@blank => nil, @serie_c => nil}, %{}, [@class_a, @class_c]))
    assert errs[@blank] == [{:in_use, ["2nde A"]}]
    assert errs[@serie_c] == [{:in_use, ["2nde C"]}]
  end

  test "an unknown group is reported on the subject" do
    errs = errors(CoefficientRules.validate(@cells, %{}, %{"maths" => :invalid}, []))
    assert errs[{:group, "maths"}] == [:invalid_group]
  end
end
