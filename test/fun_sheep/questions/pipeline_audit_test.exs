defmodule FunSheep.Questions.PipelineAuditTest do
  use FunSheep.DataCase, async: false

  import Ecto.Query

  alias FunSheep.{Repo, Questions}
  alias FunSheep.ContentFixtures
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Questions.Question

  defp create_course do
    ContentFixtures.create_course(%{catalog_test_type: "sat", catalog_subject: "mathematics"})
  end

  defp insert_source(course, attrs \\ %{}) do
    defaults = %{
      course_id: course.id,
      url: "https://example.com/#{:erlang.unique_integer([:positive])}",
      source_type: "practice_test",
      title: "Test source",
      status: "discovered",
      discovery_strategy: "web_search"
    }

    # domain is on SourceRegistryEntry, not DiscoveredSource; drop it
    attrs = Map.delete(attrs, :domain)

    %DiscoveredSource{}
    |> DiscoveredSource.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_question(course, source, attrs \\ %{}) do
    defaults = %{
      course_id: course.id,
      content: "Sample question content #{:erlang.unique_integer([:positive])}",
      answer: "A",
      question_type: :multiple_choice,
      difficulty: :medium,
      source_type: :web_scraped,
      source_url: source.url,
      validation_status: :passed
    }

    %Question{}
    |> Question.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "pipeline_audit_for_course/1" do
    test "returns zero counts for a course with no sources" do
      course = create_course()
      audit = Questions.pipeline_audit_for_course(course.id)

      assert audit.sources_discovered == 0
      assert audit.sources_scraped == 0
      assert audit.sources_failed == 0
      assert audit.questions_extracted == 0
      assert audit.questions_passed == 0
      assert audit.questions_needs_review == 0
      assert audit.questions_failed == 0
      assert audit.by_domain == []
    end

    test "counts discovered sources by status" do
      course = create_course()
      insert_source(course, %{status: "discovered"})
      insert_source(course, %{status: "scraped"})
      insert_source(course, %{status: "processed"})
      insert_source(course, %{status: "failed"})

      audit = Questions.pipeline_audit_for_course(course.id)

      assert audit.sources_discovered == 4
      assert audit.sources_scraped == 2
      assert audit.sources_failed == 1
    end

    test "counts web_scraped questions by validation_status" do
      course = create_course()
      source = insert_source(course, %{status: "processed"})

      insert_question(course, source, %{validation_status: :passed})
      insert_question(course, source, %{validation_status: :passed})
      insert_question(course, source, %{validation_status: :needs_review})
      insert_question(course, source, %{validation_status: :failed})

      audit = Questions.pipeline_audit_for_course(course.id)

      assert audit.questions_extracted == 4
      assert audit.questions_passed == 2
      assert audit.questions_needs_review == 1
      assert audit.questions_failed == 1
    end

    test "excludes non-web_scraped questions from counts" do
      course = create_course()
      source = insert_source(course, %{status: "processed"})

      insert_question(course, source, %{source_type: :ai_generated, validation_status: :passed})
      insert_question(course, source, %{source_type: :web_scraped, validation_status: :passed})

      audit = Questions.pipeline_audit_for_course(course.id)

      assert audit.questions_extracted == 1
      assert audit.questions_passed == 1
    end

    test "by_domain groups sources and questions per domain" do
      course = create_course()

      s1 = insert_source(course, %{url: "https://khanacademy.org/q1", status: "processed"})
      s2 = insert_source(course, %{url: "https://khanacademy.org/q2", status: "processed"})
      _s3 = insert_source(course, %{url: "https://collegeboard.org/q1", status: "discovered"})

      insert_question(course, s1, %{validation_status: :passed})
      insert_question(course, s1, %{validation_status: :passed})
      insert_question(course, s2, %{validation_status: :failed})

      audit = Questions.pipeline_audit_for_course(course.id)

      khan = Enum.find(audit.by_domain, &(&1.domain == "khanacademy.org"))
      college = Enum.find(audit.by_domain, &(&1.domain == "collegeboard.org"))

      assert khan != nil
      assert khan.sources == 2
      assert khan.extracted == 3
      assert khan.passed == 2
      assert khan.pass_rate == 0.67

      assert college != nil
      assert college.sources == 1
      assert college.extracted == 0
      assert college.pass_rate == 0.0
    end

    test "does not mix data between courses" do
      course1 = create_course()
      course2 = create_course()

      source1 = insert_source(course1, %{status: "processed"})
      insert_question(course1, source1, %{validation_status: :passed})

      audit2 = Questions.pipeline_audit_for_course(course2.id)
      assert audit2.sources_discovered == 0
      assert audit2.questions_extracted == 0
    end

    test "by_domain distinguishes registry vs web_search strategies" do
      course = create_course()

      s1 = insert_source(course, %{url: "https://aamc.org/q1", status: "processed", discovery_strategy: "registry"})
      s2 = insert_source(course, %{url: "https://aamc.org/q2", status: "processed", discovery_strategy: "web_search"})

      insert_question(course, s1, %{validation_status: :passed})
      insert_question(course, s2, %{validation_status: :passed})

      audit = Questions.pipeline_audit_for_course(course.id)

      registry_row = Enum.find(audit.by_domain, &(&1.domain == "aamc.org" and &1.strategy == "registry"))
      web_row = Enum.find(audit.by_domain, &(&1.domain == "aamc.org" and &1.strategy == "web_search"))

      assert registry_row != nil
      assert web_row != nil
    end
  end
end
