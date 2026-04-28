# Testing

Roe uses Minitest with FactoryBot for testing. This guide covers conventions, setup, and best practices.

## Test Framework

### Minitest (Not RSpec)

Roe uses Rails default Minitest:

```ruby
# test/models/post_test.rb
require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "should be valid with title" do
    post = build(:post, title: "Hello")
    assert post.valid?
  end
end
```

**Graph Note:** Testing conventions are documented in AGENTS.md and verified through graph analysis of test file structure.

## Test Structure

```
test/
├── test_helper.rb           # Global test configuration
├── factories.rb             # FactoryBot definitions
├── test_helpers/
│   └── session_test_helper.rb  # Auth helpers
├── controllers/
├── models/
├── services/
├── mailers/
├── helpers/
└── integration/
```

## FactoryBot

### Configuration

```ruby
# test/factories.rb
FactoryBot.define do
  factory :post do
    title { "Test Post" }
    slug { "test-post" }
    content { "Test content" }
    status { :published }
    
    trait :draft do
      status { :draft }
    end
    
    trait :paid do
      audience { :paid }
    end
  end
  
  factory :member do
    email { "member@example.com" }
    
    trait :paid do
      subscription_status { :active }
      stripe_customer_id { "cus_123" }
    end
  end
end
```

### Usage

```ruby
# Create (saves to database)
post = create(:post)
member = create(:member, :paid)

# Build (not saved)
post = build(:post, title: "Custom")

# Attributes hash
attrs = attributes_for(:post)
```

## Writing Tests

### Model Tests

```ruby
# test/models/post_test.rb
require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    @post = create(:post)
  end
  
  test "valid with required attributes" do
    assert @post.valid?
  end
  
  test "invalid without title" do
    @post.title = nil
    assert_not @post.valid?
    assert_includes @post.errors[:title], "can't be blank"
  end
  
  test "generates slug from title" do
    post = create(:post, title: "Hello World")
    assert_equal "hello-world", post.slug
  end
  
  test "paid member can access premium content" do
    member = create(:member, :paid)
    post = create(:post, :paid)
    
    assert member.can_access?(post)
  end
  
  test "free member cannot access premium content" do
    member = create(:member)
    post = create(:post, :paid)
    
    assert_not member.can_access?(post)
  end
end
```

### Controller Tests

```ruby
# test/controllers/admin/posts_controller_test.rb
require "test_helper"

class Admin::PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, :admin)
    sign_in_as(@admin)
  end
  
  test "should get index" do
    get admin_posts_url
    assert_response :success
  end
  
  test "should create post" do
    assert_difference("Post.count") do
      post admin_posts_url, params: {
        post: attributes_for(:post)
      }
    end
    
    assert_redirected_to admin_post_url(Post.last)
  end
  
  test "should require authentication" do
    sign_out
    get admin_posts_url
    assert_redirected_to signin_url
  end
end
```

### Service Tests

```ruby
# test/services/content_sync_test.rb
require "test_helper"

class ContentSyncTest < ActiveSupport::TestCase
  test "syncs post from file" do
    # Create test file
    File.write("tmp/test-post.md", <<~MD)
      ---
      title: "Test"
      ---
      Content here
    MD
    
    # Sync
    ContentSync.sync_file("tmp/test-post.md")
    
    # Verify
    post = Post.find_by(slug: "test-post")
    assert_equal "Test", post.title
    assert_equal "Content here", post.content.body.to_s.strip
  ensure
    File.delete("tmp/test-post.md") if File.exist?("tmp/test-post.md")
  end
end
```

### Mailer Tests

```ruby
# test/mailers/member_mailer_test.rb
require "test_helper"

class MemberMailerTest < ActionMailer::TestCase
  test "magic link email" do
    member = create(:member)
    member.generate_token!
    
    email = MemberMailer.magic_link(member)
    
    assert_equal [member.email], email.to
    assert_includes email.body.to_s, member.token
    assert_includes email.body.to_s, "signin_with_token"
  end
end
```

## Authentication in Tests

### Test Helpers

```ruby
# test/test_helpers/session_test_helper.rb
module SessionTestHelper
  def sign_in_as(user)
    post sessions_url, params: { email: user.email }
    follow_redirect!
  end
  
  def sign_in_as_member(member)
    post members_sessions_url, params: { token: member.token }
  end
  
  def sign_out
    delete session_url
  end
end
```

### Usage

```ruby
class Members::AccountsControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper
  
  setup do
    @member = create(:member)
    sign_in_as_member(@member)
  end
  
  test "should show account" do
    get members_account_url
    assert_response :success
  end
end
```

## Running Tests

### All Tests

```bash
bin/rails test
```

### Single File

```bash
bin/rails test test/models/post_test.rb
```

### Single Test

```bash
# By name
bin/rails test -n test_should_be_valid

# By line number
bin/rails test test/models/post_test.rb:4
```

### With Coverage

```bash
bin/rails test:all
# Generates coverage/ directory
```

## Fixtures vs Factories

### When to Use Fixtures

- Static reference data (e.g., default site config)
- Data that rarely changes
- Cross-test dependencies

```yaml
# test/fixtures/site_configs.yml
default:
  title: "Test Site"
  url: "http://localhost:3000"
```

### When to Use Factories

- Dynamic test data
- Variations of same model
- Complex relationships

## Best Practices

### 1. Independent Tests

Each test should be independent:

```ruby
# Bad
setup do
  @post = create(:post)  # Shared state
end

test "first" do
  @post.destroy  # Affects next test!
end

# Good
setup do
  @post = create(:post)
end

test "first" do
  post_copy = Post.find(@post.id)
  post_copy.destroy
  # @post still valid for next test
end
```

### 2. Clear Assertions

```ruby
# Bad
assert post.valid?

# Good
assert post.valid?, "Post should be valid with title: #{post.title}"
```

### 3. Test Edge Cases

```ruby
test "handles special characters in title" do
  post = build(:post, title: "Hello & Welcome <script>")
  assert post.valid?
  assert_includes post.slug, "hello-welcome-script"
end
```

### 4. Test Business Logic

```ruby
# Test the rule, not the implementation
test "paid content requires subscription" do
  # Setup
  post = create(:post, :paid)
  free_member = create(:member)
  paid_member = create(:member, :paid)
  
  # Exercise & Verify
  assert_not free_member.can_access?(post)
  assert paid_member.can_access?(post)
end
```

### 5. Clean Up After Tests

```ruby
test "creates file" do
  path = "tmp/test-#{Time.now.to_i}.txt"
  
  File.write(path, "content")
  assert File.exist?(path)
ensure
  File.delete(path) if File.exist?(path)
end
```

## Testing Content Sync

```ruby
test "sync detects file changes" do
  # Create initial file
  file_path = "tmp/sync-test.md"
  File.write(file_path, "---\ntitle: V1\n---\nContent")
  
  # First sync
  ContentSync.sync_file(file_path)
  post = Post.find_by(slug: "sync-test")
  assert_equal "V1", post.title
  
  # Modify file
  File.write(file_path, "---\ntitle: V2\n---\nContent")
  
  # Second sync
  ContentSync.sync_file(file_path)
  post.reload
  assert_equal "V2", post.title
ensure
  File.delete(file_path) if File.exist?(file_path)
  Post.find_by(slug: "sync-test")&.destroy
end
```

## Testing Static Generation

```ruby
test "generates static files" do
  post = create(:post, :published)
  
  StaticGenerator.generate_post(post)
  
  output_path = "output/posts/#{post.slug}.html"
  assert File.exist?(output_path)
  assert_includes File.read(output_path), post.title
ensure
  FileUtils.rm_rf("output/posts/#{post.slug}.html")
end
```

## Testing Services

```ruby
test "converter extracts plain text" do
  html = "<p>Hello <strong>world</strong></p>"
  
  text = Converter.plain_text(html)
  
  assert_equal "Hello world", text
end
```

## Integration Tests

```ruby
test "complete signup flow" do
  # Visitor requests magic link
  post members_sessions_path, params: { email: "new@example.com" }
  
  # Email sent
  assert_emails 1
  email = ActionMailer::Base.deliveries.last
  
  # Extract token from email
  token = email.body.to_s.match(/token=([a-z0-9]+)/)[1]
  
  # Visitor clicks link
  get members_signin_path(token: token)
  
  # Redirected to account
  assert_redirected_to members_account_path
  
  # Member created
  assert Member.exists?(email: "new@example.com")
end
```

## Continuous Integration

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2.2'
          bundler-cache: true
      
      - name: Setup Database
        run: bin/rails db:test:prepare
      
      - name: Run Tests
        run: bin/rails test
```

## Debugging Failed Tests

### Verbose Output

```bash
bin/rails test -v
```

### Stop on First Failure

```bash
bin/rails test --fail-fast
```

### Run with Debugger

```ruby
test "something" do
  binding.break  # Stops here
  # ...
end
```

### Check Test Database

```bash
RAILS_ENV=test bin/rails console

# In console
Post.count
Member.last
```

## Related

- [Extending](./09-extending.md) - Adding features that need tests
- [Troubleshooting](./18-troubleshooting.md) - When tests fail
- [Architecture](./01-architecture.md) - System overview
