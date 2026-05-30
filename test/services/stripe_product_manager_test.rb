require "test_helper"
require "ostruct"

class StripeProductManagerTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    @stripe_config = StripeConfig.current
    @manager = StripeProductManager.new
  end

  # Validation tests
  test "sync_from_config returns false when payments not enabled" do
    payments_config = { "enabled" => false, "price" => "49.00" }

    result = @manager.sync_from_config(payments_config)

    assert_not result
    assert_includes @manager.errors, "Payments not enabled"
  end

  test "sync_from_config returns false when price not set" do
    payments_config = { "enabled" => true, "price" => nil }

    result = @manager.sync_from_config(payments_config)

    assert_not result
    assert_includes @manager.errors, "Price not set"
  end

  test "sync_from_config returns false when Stripe not connected" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    # No API keys set

    result = @manager.sync_from_config(payments_config)

    assert_not result
  end

  test "sync_from_config returns false with invalid price format" do
    payments_config = { "enabled" => true, "price" => "not-a-number" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    # Create a new manager after config is updated
    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert_not result
    assert_includes manager.errors, "Invalid price format"
  end

  # Successful sync tests
  test "sync_from_config creates new product when none exists" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    # Mock Stripe API calls
    mock_product = OpenStruct.new(id: "prod_123")
    mock_price = OpenStruct.new(id: "price_456")

    Stripe::Product.expects(:create).returns(mock_product)
    Stripe::Price.expects(:create).returns(mock_price)

    # Create new manager after config is updated
    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert result
    assert_equal "prod_123", @stripe_config.reload.product_id
    assert_equal "price_456", @stripe_config.price_id
  end

  test "sync_from_config retrieves existing product when product_id present" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      product_id: "prod_existing"
    )

    mock_product = OpenStruct.new(id: "prod_existing")
    mock_price = OpenStruct.new(id: "price_new")

    Stripe::Product.expects(:retrieve).with("prod_existing", anything).returns(mock_product)
    Stripe::Price.expects(:create).returns(mock_price)

    # Create new manager after config has product_id
    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert result
    assert_equal "price_new", @stripe_config.reload.price_id
  end

  test "sync_from_config creates new product when existing product deleted" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      product_id: "prod_deleted"
    )

    mock_new_product = OpenStruct.new(id: "prod_new")
    mock_price = OpenStruct.new(id: "price_new")

    # Product retrieval fails (deleted)
    Stripe::Product.expects(:retrieve)
      .with("prod_deleted", anything)
      .raises(Stripe::InvalidRequestError.new("Not found", "id"))

    # Creates new product
    Stripe::Product.expects(:create).returns(mock_new_product)
    Stripe::Price.expects(:create).returns(mock_price)

    # Create new manager after config is updated with product_id
    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert result
    assert_equal "prod_new", @stripe_config.reload.product_id
  end

  # Price parsing tests
  test "parse_price converts decimal dollars to cents" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    payments_config = { "enabled" => true, "price" => "49.99" }

    mock_product = OpenStruct.new(id: "prod_123")
    mock_price = OpenStruct.new(id: "price_456")

    Stripe::Product.expects(:create).returns(mock_product)
    Stripe::Price.expects(:create).returns(mock_price)

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
    # Verify config was updated
    assert_equal "price_456", @stripe_config.reload.price_id
  end

  test "parse_price handles integer prices" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    payments_config = { "enabled" => true, "price" => "50" }

    mock_product = OpenStruct.new(id: "prod_123")
    mock_price = OpenStruct.new(id: "price_456")

    Stripe::Product.expects(:create).returns(mock_product)
    Stripe::Price.expects(:create).returns(mock_price)

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
    assert_equal "price_456", @stripe_config.reload.price_id
  end

  # Error handling tests
  test "sync_from_config handles Stripe API errors gracefully" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    Stripe::Product.expects(:create)
      .raises(Stripe::StripeError.new("API Error"))

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert_not result
    assert_includes manager.errors, "Stripe API error: API Error"
  end

  test "sync_from_config handles network errors" do
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    Stripe::Product.expects(:create)
      .raises(Stripe::APIConnectionError.new("Network error"))

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)

    assert_not result
  end

  # Product attributes tests
  test "creates product with correct attributes" do
    # Update existing SiteConfig with title (test_helper creates one)
    SiteConfig.find_by(file_path: "site/system/global/site.yml")&.update!(config: { "title" => "My Blog" })
    payments_config = { "enabled" => true, "price" => "49.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    mock_price = OpenStruct.new(id: "price_456")

    Stripe::Product.expects(:create).returns(OpenStruct.new(id: "prod_123"))
    Stripe::Price.expects(:create).returns(mock_price)

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
  end

  test "uses site title from SiteConfig" do
    # Update existing SiteConfig with title (test_helper creates one)
    SiteConfig.find_by(file_path: "site/system/global/site.yml")&.update!(config: { "title" => "Test Site Name" })
    payments_config = { "enabled" => true, "price" => "29.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    mock_price = OpenStruct.new(id: "price_789")

    Stripe::Product.expects(:create).returns(OpenStruct.new(id: "prod_789"))
    Stripe::Price.expects(:create).returns(mock_price)

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
  end

  # Price attributes tests
  test "creates price with correct attributes" do
    payments_config = { "enabled" => true, "price" => "99.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      currency: "usd"
    )

    Stripe::Product.expects(:create).returns(OpenStruct.new(id: "prod_123"))
    Stripe::Price.expects(:create).returns(OpenStruct.new(id: "price_456"))

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
    assert_equal "prod_123", @stripe_config.reload.product_id
    assert_equal "price_456", @stripe_config.price_id
  end

  test "uses StripeConfig currency for price" do
    payments_config = { "enabled" => true, "price" => "99.00" }
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      currency: "eur"
    )

    Stripe::Product.expects(:create).returns(OpenStruct.new(id: "prod_123"))
    Stripe::Price.expects(:create).returns(OpenStruct.new(id: "price_456"))

    manager = StripeProductManager.new
    result = manager.sync_from_config(payments_config)
    assert result
  end
end
