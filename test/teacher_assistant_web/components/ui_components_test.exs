defmodule TeacherAssistantWeb.UIComponentsTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import TeacherAssistantWeb.UIComponents

  alias TeacherAssistantWeb.{Layouts, Spaces}

  defp parse(html), do: LazyHTML.from_fragment(html)
  defp count(html, selector), do: html |> parse() |> LazyHTML.query(selector) |> Enum.count()

  defp texts(html, selector),
    do: html |> parse() |> LazyHTML.query(selector) |> Enum.map(&LazyHTML.text/1)

  describe "filter_pills" do
    test "patch links with their counts, the current one marked" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.filter_pills id="f">
          <:pill id="all" patch="/x?f=all" count={41} current>Toutes</:pill>
          <:pill id="no-pp" patch="/x?f=no_pp" count={0}>Sans PP</:pill>
          <:pill id="plain" patch="/x?f=plain">Autres</:pill>
        </.filter_pills>
        """)

      assert count(html, "nav#f a[data-phx-link=patch]") == 3
      assert count(html, "a#all[aria-current=true]") == 1
      assert count(html, "a#no-pp[aria-current]") == 0
      assert texts(html, "a#all .ta-pill__count") == ["41"]
      assert texts(html, "a#no-pp .ta-pill__count") == ["0"]
      assert count(html, "a#plain .ta-pill__count") == 0
    end
  end

  describe "class_picker" do
    @classes [
      %{id: "t", label: "Terminale C", level: "Terminale", n: 30},
      %{id: "b", label: "6ème B", level: "6ème", n: 7},
      %{id: "a", label: "6ème A", level: "6ème", n: 40},
      %{id: "c", label: "5ème", level: "5ème", n: 12}
    ]

    defp picker(current, extra \\ %{}) do
      assigns =
        Map.merge(%{classes: @classes, current: current, change: nil, suffix: nil}, extra)

      rendered_to_string(~H"""
      <.class_picker
        id="cp"
        classes={@classes}
        current={@current}
        to={fn c -> "/conduct?class=#{c.id}" end}
        change={@change}
        suffix={@suffix}
      />
      """)
    end

    test "groups the classes by level in the school order, the current one selected" do
      html = picker("b")

      assert texts(html, "optgroup") |> length() == 3

      assert html |> parse() |> LazyHTML.query("optgroup") |> LazyHTML.attribute("label") ==
               ["6ème", "5ème", "Terminale"]

      assert texts(html, "option") |> Enum.map(&String.trim/1) ==
               ["6ème A", "6ème B", "5ème", "Terminale C"]

      assert texts(html, "option[selected]") |> Enum.map(&String.trim/1) == ["6ème B"]
    end

    test "‹ › patch to the neighbouring classes and stop at the ends" do
      html = picker("b")

      assert html |> parse() |> LazyHTML.query("a#cp-prev") |> LazyHTML.attribute("href") ==
               ["/conduct?class=a"]

      assert html |> parse() |> LazyHTML.query("a#cp-next") |> LazyHTML.attribute("href") ==
               ["/conduct?class=c"]

      first = picker("a")
      assert count(first, "a#cp-prev") == 0
      assert count(first, "a#cp-next") == 1

      last = picker("t")
      assert count(last, "a#cp-next") == 0
    end

    test "adds the suffix to each option and is its own form with change" do
      html =
        picker("a", %{
          change: "pick",
          suffix: fn c -> if c.n > 10, do: "#{c.n} élèves" end
        })

      assert count(html, "form#cp-form[phx-change=pick] select[name=class]") == 1
      options = texts(html, "option") |> Enum.map(&String.trim/1)
      assert "6ème A · 40 élèves" in options
      assert "6ème B" in options
    end

    test "without change it is a bare select for the page's form" do
      html = picker(nil)
      assert count(html, "form") == 0
      assert count(html, "select[name=class]") == 1
      assert count(html, "a#cp-prev") + count(html, "a#cp-next") == 0
    end
  end

  test "level_group heads its rows with the level, classes and students" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.level_group id="lvl" level="6ème" classes={3} students={142}>ROWS</.level_group>
      """)

    [header] = texts(html, "#lvl h2")
    assert header =~ "6ème"
    assert header =~ "3 classes"
    assert header =~ "142 élèves"
    assert html =~ "ROWS"

    one =
      rendered_to_string(~H"""
      <.level_group level="Form 1" classes={1}>X</.level_group>
      """)

    assert one =~ "1 classe"
    refute one =~ "élève"
  end

  describe "progress_meter" do
    defp meter(value, total) do
      assigns = %{value: value, total: total}

      rendered_to_string(~H"""
      <.progress_meter id="m" label="Notes" value={@value} total={@total} />
      """)
    end

    test "shows x/total and a bar toned by completion" do
      partial = meter(18, 42)
      assert partial =~ "18/42"
      assert partial =~ "width: 43%"
      assert count(partial, ".bg-warning") == 1

      assert count(meter(42, 42), ".bg-primary") == 1
      assert count(meter(0, 42), ".bg-warning, .bg-primary") == 0
      assert meter(0, 0) =~ "width: 0%"
    end
  end

  test "bulk_bar shows the selection count and actions, nothing when empty" do
    assigns = %{n: 3}

    html =
      rendered_to_string(~H"""
      <.bulk_bar id="bulk" count={@n} clear="clear">
        <:actions><button>Relancer</button></:actions>
      </.bulk_bar>
      """)

    assert html =~ "3 sélectionnés"
    assert html =~ "Relancer"
    assert count(html, "button[phx-click=clear]") == 1

    assigns = %{n: 0}

    empty =
      rendered_to_string(~H"""
      <.bulk_bar id="bulk" count={@n}>
        <:actions><button>Relancer</button></:actions>
      </.bulk_bar>
      """)

    assert count(empty, "#bulk") == 0
  end

  test "attention_card lists rows with one action each, nothing when count is 0" do
    assigns = %{n: 2}

    html =
      rendered_to_string(~H"""
      <.attention_card id="todo" count={@n}>
        <.attention_row
          id="r1"
          title="6ème A sans PP"
          reason="40 élèves"
          action="Désigner"
          navigate="/c/1"
        />
        <.attention_row id="r2" title="Relance" action="Marquer" phx-click="mark" />
      </.attention_card>
      """)

    assert html =~ "À compléter"
    assert html =~ "40 élèves"
    assert count(html, "#r1 a[href='/c/1']") == 1
    assert count(html, "#r2 button[phx-click=mark]") == 1

    assigns = %{n: 0}

    empty =
      rendered_to_string(~H"""
      <.attention_card id="todo" count={@n} title="À régler">
        <.attention_row title="x" action="y" navigate="/" />
      </.attention_card>
      """)

    assert count(empty, "#todo") == 0
  end

  test "stat_tile is a link only with navigate" do
    assigns = %{}

    linked =
      rendered_to_string(~H"""
      <.stat_tile id="s" label="Appels" value="12 / 14" sub="2 en retard" tone={:warn} navigate="/day" />
      """)

    assert count(linked, "a#s[href='/day'] .ta-num.text-warning") == 1
    assert linked =~ "2 en retard"

    plain =
      rendered_to_string(~H"""
      <.stat_tile id="s" label="Élèves" value="371" />
      """)

    assert count(plain, "div#s .ta-num") == 1
    assert count(plain, "a") == 0
  end

  test "back_header in task mode puts a back arrow before the title on phones" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.back_header task back="/school/courses" title="Maths · 6ème" subtitle="2 classes">
        <:actions><button id="seq">Séq. 2</button></:actions>
      </.back_header>
      """)

    assert count(html, "a#back-header-arrow[href='/school/courses'].sm\\:hidden") == 1
    assert count(html, "#back-header-parent") == 1
    assert count(html, "h1.truncate") == 1
    assert count(html, "button#seq") == 1

    plain =
      rendered_to_string(~H"""
      <.back_header back="/school/settings" back_label="Paramètres" title="Salles" />
      """)

    assert count(plain, "#back-header-arrow") == 0
    assert count(plain, "#back-header-parent") == 1
  end

  describe "Layouts.app immersive" do
    setup :register_and_log_in_user

    defp layout(scope, immersive) do
      assigns = %{scope: scope, immersive: immersive}

      rendered_to_string(~H"""
      <Layouts.app flash={%{}} current_scope={@scope} immersive={@immersive}>
        <p id="content">Contenu</p>
      </Layouts.app>
      """)
    end

    test "hides the phone tab bar and top bar", %{actor: actor, workspace: school} do
      scope = actor |> school_scope(school) |> Spaces.put_space(nil, counts?: false)

      normal = layout(scope, false)
      assert count(normal, "#tab-bar") == 1

      immersive = layout(scope, true)
      assert count(immersive, "#tab-bar") == 0
      assert count(immersive, "#notification-bell-mobile") == 0
      assert count(immersive, "#content") == 1
    end
  end
end
