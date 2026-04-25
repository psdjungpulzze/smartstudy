defmodule FunSheep.EbookFixtures do
  @moduledoc """
  In-memory EPUB fixture builder for tests.

  Builds minimal valid EPUB ZIP archives using :zip so tests can exercise
  EpubParser and EbookExtractWorker without touching real files on disk.

  All content is minimal but structurally correct. Nothing is fake data
  masquerading as real content — these are test scaffolds used only in
  the :test environment.
  """

  @doc """
  Returns raw ZIP bytes for a minimal valid EPUB 2 archive.

  The archive contains:
    - mimetype (uncompressed, as required by EPUB spec)
    - META-INF/container.xml
    - OEBPS/content.opf (minimal OPF with one spine item)
    - OEBPS/toc.ncx (minimal NCX with one navPoint)
    - OEBPS/chapter1.xhtml (minimal XHTML with some text content)

  Opts:
    - `:title`   — book title string (default "Test Book")
    - `:author`  — author string (default "Test Author")
    - `:chapter_text` — body text for chapter1.xhtml
  """
  def minimal_epub2_bytes(opts \\ []) do
    title = Keyword.get(opts, :title, "Test Book")
    author = Keyword.get(opts, :author, "Test Author")

    chapter_text =
      Keyword.get(opts, :chapter_text, "This is the first chapter. It has some text.")

    mimetype = "application/epub+zip"

    container_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    content_opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package version="2.0" xmlns="http://www.idpf.org/2007/opf"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             xmlns:opf="http://www.idpf.org/2007/opf"
             unique-identifier="book-id">
      <metadata>
        <dc:title>#{title}</dc:title>
        <dc:creator opf:role="aut">#{author}</dc:creator>
        <dc:language>en</dc:language>
        <dc:identifier id="book-id" opf:scheme="UUID">urn:uuid:test-book-uuid-001</dc:identifier>
      </metadata>
      <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine toc="ncx">
        <itemref idref="chapter1"/>
      </spine>
    </package>
    """

    toc_ncx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
    <ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
      <head>
        <meta name="dtb:uid" content="urn:uuid:test-book-uuid-001"/>
      </head>
      <docTitle><text>#{title}</text></docTitle>
      <navMap>
        <navPoint id="navPoint-1" playOrder="1">
          <navLabel><text>Chapter 1: Introduction</text></navLabel>
          <content src="chapter1.xhtml"/>
        </navPoint>
      </navMap>
    </ncx>
    """

    chapter1_xhtml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Chapter 1</title></head>
      <body>
        <h1>Chapter 1: Introduction</h1>
        <p>#{chapter_text}</p>
      </body>
    </html>
    """

    build_epub_zip([
      {"mimetype", mimetype},
      {"META-INF/container.xml", String.trim(container_xml)},
      {"OEBPS/content.opf", String.trim(content_opf)},
      {"OEBPS/toc.ncx", String.trim(toc_ncx)},
      {"OEBPS/chapter1.xhtml", String.trim(chapter1_xhtml)}
    ])
  end

  @doc """
  Returns raw ZIP bytes for a minimal EPUB 3 archive (uses nav.xhtml).
  """
  def minimal_epub3_bytes(opts \\ []) do
    title = Keyword.get(opts, :title, "Test EPUB3 Book")
    author = Keyword.get(opts, :author, "Test Author")
    chapter_text = Keyword.get(opts, :chapter_text, "EPUB 3 chapter text goes here.")

    mimetype = "application/epub+zip"

    container_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    content_opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package version="3.0" xmlns="http://www.idpf.org/2007/opf"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             unique-identifier="book-id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>#{title}</dc:title>
        <dc:creator>#{author}</dc:creator>
        <dc:language>en</dc:language>
        <dc:identifier id="book-id">urn:uuid:epub3-test-uuid-001</dc:identifier>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="chapter1"/>
      </spine>
    </package>
    """

    nav_xhtml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <head><title>Navigation</title></head>
      <body>
        <nav epub:type="toc" id="toc">
          <h2>Table of Contents</h2>
          <ol>
            <li><a href="chapter1.xhtml">Chapter 1: Introduction</a></li>
          </ol>
        </nav>
      </body>
    </html>
    """

    chapter1_xhtml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Chapter 1</title></head>
      <body>
        <h1>Chapter 1: Introduction</h1>
        <p>#{chapter_text}</p>
      </body>
    </html>
    """

    build_epub_zip([
      {"mimetype", mimetype},
      {"META-INF/container.xml", String.trim(container_xml)},
      {"OEBPS/content.opf", String.trim(content_opf)},
      {"OEBPS/nav.xhtml", String.trim(nav_xhtml)},
      {"OEBPS/chapter1.xhtml", String.trim(chapter1_xhtml)}
    ])
  end

  @doc """
  Returns raw ZIP bytes for a DRM-protected EPUB.
  The presence of META-INF/encryption.xml is sufficient to trigger DRM detection.
  """
  def drm_epub_bytes do
    mimetype = "application/epub+zip"

    container_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    encryption_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
        <EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
      </EncryptedData>
    </encryption>
    """

    build_epub_zip([
      {"mimetype", mimetype},
      {"META-INF/container.xml", String.trim(container_xml)},
      {"META-INF/encryption.xml", String.trim(encryption_xml)}
    ])
  end

  @doc """
  Returns bytes that are NOT a valid ZIP (simulates a corrupt/wrong file).
  """
  def corrupt_epub_bytes do
    "this is not a valid epub zip file at all"
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp build_epub_zip(entries) do
    # Convert to :zip format: list of {charlist_name, binary_content}
    zip_entries =
      Enum.map(entries, fn {name, content} ->
        {String.to_charlist(name), to_string(content)}
      end)

    case :zip.zip(~c"epub.zip", zip_entries, [:memory]) do
      {:ok, {_name, bytes}} -> bytes
      {:error, reason} -> raise "Failed to build test EPUB fixture: #{inspect(reason)}"
    end
  end
end
