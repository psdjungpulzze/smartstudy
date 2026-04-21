defmodule FunSheep.Accounts.RoleResolverTest do
  use ExUnit.Case, async: true

  alias FunSheep.Accounts.RoleResolver

  describe "resolve/2 — admin is a trusted claim" do
    test "admin claim wins even when selected_role is a safe role" do
      assert RoleResolver.resolve("admin", "student") == "admin"
      assert RoleResolver.resolve("admin", "teacher") == "admin"
      assert RoleResolver.resolve("admin", "parent") == "admin"
    end

    test "admin claim wins even when selected_role is nil" do
      assert RoleResolver.resolve("admin", nil) == "admin"
    end
  end

  describe "resolve/2 — privilege escalation is blocked" do
    test "user-supplied 'admin' does NOT grant admin without the claim" do
      assert RoleResolver.resolve("student", "admin") == "student"
      assert RoleResolver.resolve("teacher", "admin") == "teacher"
    end

    test "unknown selected_role falls back to claim role" do
      assert RoleResolver.resolve("teacher", "hacker") == "teacher"
    end

    test "unknown claim role falls back to student" do
      assert RoleResolver.resolve("garbage", nil) == "student"
      assert RoleResolver.resolve(nil, nil) == "student"
    end
  end

  describe "resolve/2 — context switching for multi-role users" do
    test "safe selected_role overrides safe claim role" do
      # A user whose Interactor metadata.role is 'student' can switch to
      # their teacher session if they have one.
      assert RoleResolver.resolve("student", "teacher") == "teacher"
      assert RoleResolver.resolve("teacher", "student") == "student"
    end
  end

  describe "normalize/1" do
    test "accepts known roles" do
      for role <- ~w(student parent teacher admin) do
        assert RoleResolver.normalize(role) == role
      end
    end

    test "returns nil for anything else" do
      assert RoleResolver.normalize("hacker") == nil
      assert RoleResolver.normalize(nil) == nil
      assert RoleResolver.normalize(:student) == nil
    end
  end
end
