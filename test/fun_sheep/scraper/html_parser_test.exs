defmodule FunSheep.Scraper.HtmlParserTest do
  use ExUnit.Case, async: true

  alias FunSheep.Scraper.HtmlParser

  describe "parse/1" do
    test "extracts plain text from a simple HTML page" do
      html = """
      <html>
        <body>
          <main><p>What is 2 + 2?</p></main>
        </body>
      </html>
      """

      result = HtmlParser.parse(html)
      assert result =~ "What is 2 + 2?"
    end

    test "strips nav, header, footer, and script tags" do
      html = """
      <html>
        <body>
          <header>Site Header</header>
          <nav>Navigation Links</nav>
          <main><p>The question is here.</p></main>
          <footer>Footer Content</footer>
          <script>alert('xss')</script>
        </body>
      </html>
      """

      result = HtmlParser.parse(html)
      assert result =~ "question is here"
      refute result =~ "Site Header"
      refute result =~ "Navigation Links"
      refute result =~ "Footer Content"
      refute result =~ "alert"
    end

    test "preserves ordered list numbering for MCQ options" do
      html = """
      <html><body><main>
        <p>Which of the following is correct?</p>
        <ol>
          <li>Option A content</li>
          <li>Option B content</li>
          <li>Option C content</li>
          <li>Option D content</li>
        </ol>
      </main></body></html>
      """

      result = HtmlParser.parse(html)
      assert result =~ "1."
      assert result =~ "Option A content"
      assert result =~ "Option B content"
    end

    test "handles empty or whitespace-only HTML" do
      result = HtmlParser.parse("   ")
      assert is_binary(result)
    end

    test "falls back gracefully on malformed HTML" do
      result = HtmlParser.parse("<<<not html>>>")
      assert is_binary(result)
    end

    test "strips advertisement containers" do
      html = """
      <html><body><main>
        <p>Real question content here.</p>
        <div class="advertisement">Buy now!</div>
      </main></body></html>
      """

      result = HtmlParser.parse(html)
      assert result =~ "Real question content"
      refute result =~ "Buy now"
    end

    test "collapses excessive whitespace" do
      html = "<html><body><main><p>Hello   world</p></main></body></html>"
      result = HtmlParser.parse(html)
      refute result =~ "   "
    end
  end
end
