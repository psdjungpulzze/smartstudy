defmodule FunSheepWeb.Components.LikeButton do
  @moduledoc """
  A like/dislike button pair for courses.

  Usage in a LiveView:

      <.like_button
        course_id={@course.id}
        like_count={@course.like_count}
        dislike_count={@course.dislike_count}
        user_reaction={@user_reaction}
      />

  The parent LiveView must handle the `"react_to_course"` event and expose
  `course_id` and `reaction` params. See `FunSheep.Community.react_to_course/3`.
  """

  use Phoenix.Component

  attr :course_id, :string, required: true
  attr :like_count, :integer, default: 0
  attr :dislike_count, :integer, default: 0
  attr :user_reaction, :string, default: nil
  attr :class, :string, default: ""

  def like_button(assigns) do
    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <button
        phx-click="react_to_course"
        phx-value-course_id={@course_id}
        phx-value-reaction="like"
        class={[
          "flex items-center gap-1 px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
          if(@user_reaction == "like",
            do: "bg-[#4CD964] text-white",
            else:
              "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300 hover:bg-[#E8F8EB] hover:text-[#4CD964]"
          )
        ]}
        aria-label="Like this course"
        aria-pressed={@user_reaction == "like"}
      >
        <svg
          class="w-4 h-4"
          fill={if @user_reaction == "like", do: "currentColor", else: "none"}
          stroke="currentColor"
          stroke-width="1.5"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M6.633 10.5c.806 0 1.533-.446 2.031-1.08a9.041 9.041 0 012.861-2.4c.723-.384 1.35-.956 1.653-1.715a4.498 4.498 0 00.322-1.672V3a.75.75 0 01.75-.75A2.25 2.25 0 0116.5 4.5c0 1.152-.26 2.243-.723 3.218-.266.558.107 1.282.725 1.282h3.126c1.026 0 1.945.694 2.054 1.715.045.422.068.85.068 1.285a11.95 11.95 0 01-2.649 7.521c-.388.482-.987.729-1.605.729H13.48c-.483 0-.964-.078-1.423-.23l-3.114-1.04a4.501 4.501 0 00-1.423-.23H5.904M14.25 9h2.25M5.904 18.75c.083.205.173.405.27.602.197.4-.078.898-.523.898h-.908c-.889 0-1.713-.518-1.972-1.368a12 12 0 01-.521-3.507c0-1.553.295-3.036.831-4.398C3.387 10.203 4.167 9.75 5 9.75h1.053c.472 0 .745.556.5.96a8.958 8.958 0 00-1.302 4.665c0 1.194.232 2.333.654 3.375z"
          />
        </svg>
        <span>{@like_count}</span>
      </button>

      <button
        phx-click="react_to_course"
        phx-value-course_id={@course_id}
        phx-value-reaction="dislike"
        class={[
          "flex items-center gap-1 px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
          if(@user_reaction == "dislike",
            do: "bg-[#FF3B30] text-white",
            else:
              "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300 hover:bg-red-50 hover:text-[#FF3B30]"
          )
        ]}
        aria-label="Dislike this course"
        aria-pressed={@user_reaction == "dislike"}
      >
        <svg
          class="w-4 h-4"
          fill={if @user_reaction == "dislike", do: "currentColor", else: "none"}
          stroke="currentColor"
          stroke-width="1.5"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.5 15h2.25m8.024-9.75c.011.05.028.1.052.148.591 1.2.924 2.55.924 3.977a8.96 8.96 0 01-.999 4.125m.023-8.25c-.076-.365.183-.75.575-.75h.908c.889 0 1.713.518 1.972 1.368.339 1.11.521 2.287.521 3.507 0 1.553-.295 3.036-.831 4.398C20.613 14.547 19.833 15 19 15h-1.053c-.472 0-.745-.556-.5-.96a8.95 8.95 0 00.303-.54m.023-8.25H16.48a4.5 4.5 0 01-1.423-.23l-3.114-1.04a4.5 4.5 0 00-1.423-.23H6.504c-.618 0-1.217.247-1.605.729A11.95 11.95 0 002.25 12c0 .434.023.863.068 1.285C2.427 14.306 3.346 15 4.372 15h3.126c.618 0 .991.724.725 1.282A7.471 7.471 0 007.5 19.5a2.25 2.25 0 002.25 2.25.75.75 0 00.75-.75v-.633c0-.573.11-1.14.322-1.672.304-.76.93-1.33 1.653-1.715a9.04 9.04 0 002.861-2.4c.498-.634 1.226-1.08 2.032-1.08h.384"
          />
        </svg>
        <span>{@dislike_count}</span>
      </button>
    </div>
    """
  end
end
