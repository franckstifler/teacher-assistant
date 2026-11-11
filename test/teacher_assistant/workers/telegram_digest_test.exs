defmodule TeacherAssistant.Workers.TelegramDigestTest do
  # Sets the Telegram config for the whole node: not async.
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  import TeacherAssistant.TelegramHelpers

  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Workers.TelegramDigest

  @now ~U[2026-11-07 06:00:00Z]

  test "without Telegram set up, the morning job sends nothing" do
    stub_telegram()
    assert :ok = perform_job(TelegramDigest, %{})
    refute_received {:telegram, _, _}
  end

  describe "with Telegram set up" do
    setup do
      set_up_telegram()
      stub_telegram()
      :ok
    end

    test "names the schools waiting to be verified, with a link to the console" do
      %{workspace: pending} =
        TeacherFixtures.setup_complete_school_fixture(%{verified: false, name: "Lycée de Kribi"})

      assert :ok = perform_job(TelegramDigest, %{})

      assert_received {:telegram, _, %{"text" => text}}
      assert text =~ "Scolaka · point du matin"
      assert text =~ "À vérifier : 1\n• #{pending.name} (aujourd'hui)"
      assert text =~ "/admin"
      refute text =~ "Rien à traiter"
    end

    test "says so when there is nothing to handle" do
      assert :ok = perform_job(TelegramDigest, %{})

      assert_received {:telegram, _, %{"text" => text}}
      assert text =~ "Rien à traiter."
    end
  end

  describe "text/2" do
    defp school(n, days_ago),
      do: %{name: "Lycée #{n}", since: DateTime.add(@now, -days_ago, :day)}

    test "names five schools per list and counts the rest" do
      digest = %{
        pending: for(n <- 1..7, do: school(n, n)),
        quiet: [%{name: "Collège Calme", last_at: DateTime.add(@now, -20, :day)}],
        silent: [],
        open_errors: 3,
        failed_jobs: 0,
        swept_files: nil,
        first_steps: []
      }

      text = TelegramDigest.text(digest, @now)

      assert text =~ "À vérifier : 7\n• Lycée 1 (depuis 1 jour)\n• Lycée 2 (depuis 2 jours)"
      assert text =~ "• Lycée 5 (depuis 5 jours)\n• et 2 autres"
      refute text =~ "Lycée 6"
      assert text =~ "Silencieuses depuis 14 jours : 1\n• Collège Calme (depuis 20 jours)"
      assert text =~ "Erreurs ouvertes : 3"
      refute text =~ "jamais utilisées"
      refute text =~ "Tâches abandonnées"
    end

    test "first steps come after what to handle, without hiding « Rien à traiter »" do
      digest = %{
        pending: [],
        quiet: [],
        silent: [],
        open_errors: 0,
        failed_jobs: 0,
        swept_files: nil,
        first_steps: [
          %{name: "Lycée de Kribi", steps: [:students, :marks]},
          %{name: "Collège Nkam", steps: [:bulletins]}
        ]
      }

      text = TelegramDigest.text(digest, @now)

      assert text =~
               "Rien à traiter.\n\nPremiers pas depuis hier : 2\n" <>
                 "• Lycée de Kribi : élèves inscrits, premières notes\n" <>
                 "• Collège Nkam : premiers bulletins publiés"
    end
  end

  describe "the weekly sweep (A9)" do
    test "the morning text names the files the sweep deleted this week" do
      digest = %{
        pending: [],
        quiet: [],
        silent: [],
        open_errors: 0,
        failed_jobs: 0,
        first_steps: [],
        swept_files: 4
      }

      assert TelegramDigest.text(digest, DateTime.utc_now()) =~
               "Fichiers orphelins supprimés cette semaine : 4"
    end

    test "the morning text says when the sweep stopped instead (minors)" do
      digest = %{
        pending: [],
        quiet: [],
        silent: [],
        open_errors: 0,
        failed_jobs: 0,
        first_steps: [],
        swept_files: 0,
        sweep_refused: true
      }

      assert TelegramDigest.text(digest, DateTime.utc_now()) =~ "Nettoyage des fichiers suspendu"
    end
  end
end
