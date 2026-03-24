FactoryBot.define do
  factory :post do
    sequence(:file_path) { |n| "site/posts/test-post-#{n}.md" }
    content { "# Test Post\n\nTest content." }
    metadata { { "title" => "Test Post", "status" => "published", "date" => "2024-01-01" } }
  end

  factory :page do
    sequence(:file_path) { |n| "site/pages/test-page-#{n}.md" }
    content { "# Test Page\n\nTest content." }
    metadata { { "title" => "Test Page" } }
  end

  factory :documentation do
    sequence(:file_path) { |n| "site/documentation/test-doc-#{n}.md" }
    content { "# Test Documentation\n\nTest content." }
    metadata { { "title" => "Test Doc" } }
  end

  factory :medium do
    sequence(:file_path) { |n| "site/media/images/test-image-#{n}.jpg" }
    media_type { "image" }
    uploaded_at { Time.current }
  end

  factory :site_config do
    sequence(:file_path) { |n| "site/system/test-config-#{n}.yml" }
    config { { "title" => "Test Site" } }
  end

  factory :user do
    sequence(:email_address) { |n| "test#{n}@example.com" }
    password_digest { BCrypt::Password.create("password") }
  end
end
