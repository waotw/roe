module MarkdownFixture
  SIMPLE_CONTENT = <<~MARKDOWN
    # Simple Post
    
    This is a simple post with basic markdown.
    
    ## Section
    
    Some text with **bold** and *italic* text.
    
    [A link](https://example.com)
  MARKDOWN

  CODE_BLOCK_RUBY = <<~MARKDOWN
    ```ruby
    def hello
      puts "Hello, World!"
    end
    ```
  MARKDOWN

  CODE_BLOCK_JS = <<~MARKDOWN
    ```javascript
    function greet() {
      console.log("Hello!");
    }
    ```
  MARKDOWN

  CODE_BLOCK_FOUR_BACKTICKS = <<~MARKDOWN
    ````markdown
    # Code with four backticks
    
    This should be preserved.
    ````
  MARKDOWN

  GALLERY_SIMPLE = <<~MARKDOWN
    ```gallery
    ![Mountain](mountain.jpg)
    ![Ocean](ocean.jpg)
    ![Forest](forest.jpg)
    ```
  MARKDOWN

  GALLERY_WITH_CAPTIONS = <<~MARKDOWN
    ```gallery
    ![Mountain](mountain.jpg)(*The majestic peak*)
    ![Ocean](ocean.jpg)(*Calm waters*)
    ```
  MARKDOWN

  CONSECUTIVE_IMAGES = <<~MARKDOWN
    ![Photo 1](photo1.jpg)
    ![Photo 2](photo2.jpg)
    ![Photo 3](photo3.jpg)
    
    Some text between.
    
    ![Photo 4](photo4.jpg)
    ![Photo 5](photo5.jpg)
  MARKDOWN

  PULLQUOTE_CENTER = <<~MARKDOWN
    ```card
    type: pullquote
    text: "The only way to do great work is to love what you do."
    attribution: Steve Jobs
    position: center
    ```
  MARKDOWN

  PULLQUOTE_LEFT = <<~MARKDOWN
    ```card
    type: pullquote
    text: "Float this to the left side."
    attribution: Test Author
    position: left
    ```
  MARKDOWN

  PULLQUOTE_RIGHT = <<~MARKDOWN
    ```card
    type: pullquote
    text: "Float this to the right side."
    position: right
    ```
  MARKDOWN

  ASIDE_SIMPLE = <<~MARKDOWN
    ```card
    type: aside
    text: "This is an aside with additional information."
    ```
  MARKDOWN

  ASIDE_WITH_LINK = <<~MARKDOWN
    ```card
    type: aside
    text: "Learn more about this topic."
    link: /related-page
    link_text: "Read more"
    ```
  MARKDOWN

  ASIDE_WITH_IMAGE = <<~MARKDOWN
    ```card
    type: aside
    text: "Side panel content"
    image: /media/images/sidebar.jpg
    ```
  MARKDOWN

  POST_LINK_SMALL = <<~MARKDOWN
    ```card
    type: post-link
    post: hello-world
    style: small
    ```
  MARKDOWN

  POST_LINK_LARGE = <<~MARKDOWN
    ```card
    type: post-link
    post: hello-world
    style: large
    ```
  MARKDOWN

  POST_LINK_OVERRIDE = <<~MARKDOWN
    ```card
    type: post-link
    post: hello-world
    title: Custom Title
    link_text: "See full post"
    image: /custom/image.jpg
    ```
  MARKDOWN

  COLLECTION_SIMPLE = <<~MARKDOWN
    ```collection
    heading: Latest Posts
    limit: 5
    ```
  MARKDOWN

  COLLECTION_WITH_FILTERS = <<~MARKDOWN
    ```collection
    heading: Ruby Articles
    source: posts
    post_type: article
    tags: ruby
    order: date
    limit: 10
    ```
  MARKDOWN

  COLLECTION_COMPACT = <<~MARKDOWN
    ```collection
    heading: Recent
    template: compact
    limit: 3
    ```
  MARKDOWN

  COLLECTION_LINKS = <<~MARKDOWN
    ```collection
    heading: Quick Links
    template: links
    tags: important
    ```
  MARKDOWN

  COLLECTION_WITH_SHOW_MORE = <<~MARKDOWN
    ```collection
    heading: Featured Articles
    limit: 3
    show_more: true
    show_more_text: "View all articles"
    ```
  MARKDOWN

  COLLECTION_EXCLUDE_TAGS = <<~MARKDOWN
    ```collection
    heading: Non-Archived
    tags: -archived
    ```
  MARKDOWN

  FOOTNOTE_AUTO_NUMBERED = <<~MARKDOWN
    This is text with a footnote(*This is the footnote*).
    
    And another(*Second footnote here*).
  MARKDOWN

  FOOTNOTE_CUSTOM_MARKER = <<~MARKDOWN
    According to research(*[source] Scientific Journal*),
    this phenomenon occurs frequently.
  MARKDOWN

  FOOTNOTE_MIXED = <<~MARKDOWN
    First statement(*Auto numbered footnote*).
    
    Second statement(*[cite] Custom citation*).
    
    Third statement(*Another auto footnote*).
  MARKDOWN

  PULLQUOTE_SPLIT_MANUAL = <<~MARKDOWN
    This is the first part of the paragraph.||This is the second part.
  MARKDOWN

  COMPLEX_CONTENT = <<~MARKDOWN
    # Complex Post
    
    Some introductory text.
    
    ```collection
    heading: Related Posts
    limit: 3
    ```
    
    A paragraph between.
    
    ```card
    type: pullquote
    text: "Important quote here."
    position: center
    ```
    
    More content.
    
    ```gallery
    ![Image 1](img1.jpg)
    ![Image 2](img2.jpg)
    ```
    
    ## Code Example
    
    ```ruby
    def test
      puts "Hello"
    end
    ```
  MARKDOWN

  CONSECUTIVE_COLLECTIONS = <<~MARKDOWN
    ```collection
    heading: Featured
    limit: 2
    ```
    
    ```collection
    heading: Recent
    limit: 3
    ```
  MARKDOWN
end
