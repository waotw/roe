require "test_helper"

# ProductGroup is a derived value object (no table): it buckets products by
# their `group:` front-matter, keeps groups together, floats each group to its
# most-recently-edited member, puts the primary on top, and surfaces the
# no/duplicate-primary setup warnings.
class ProductGroupTest < ActiveSupport::TestCase
  def product(file, title:, group: nil, primary: false, updated: Time.current, status: "published")
    meta = { "title" => title, "status" => status }
    meta["group"] = group if group
    meta["primary"] = true if primary
    p = Product.create!(file_path: file, metadata: meta)
    p.update_column(:updated_at, updated) # control ordering deterministically
    p
  end

  test "ungrouped products are standalone rows, most recently edited first" do
    a = product("a.md", title: "A", updated: Time.at(300))
    b = product("b.md", title: "B", updated: Time.at(500))
    c = product("c.md", title: "C", updated: Time.at(100))

    rows = ProductGroup.rows_for([ a, b, c ])

    assert_equal [ b, a, c ], rows, "sorted by updated_at desc"
    assert rows.all? { |r| r.is_a?(Product) }, "no groups formed"
  end

  test "2+ products sharing a group become a ProductGroup; a lone group value stays standalone" do
    g1 = product("g1.md", title: "G1", group: "Boots")
    g2 = product("g2.md", title: "G2", group: "Boots")
    solo = product("solo.md", title: "Solo", group: "OnlyMe")

    rows = ProductGroup.rows_for([ g1, g2, solo ])

    groups = rows.select { |r| r.is_a?(ProductGroup) }
    assert_equal 1, groups.size
    assert_equal "Boots", groups.first.name
    assert_includes rows, solo, "lone group value renders as a plain product"
  end

  test "a group floats to its most recently edited member and stays together, primary on top" do
    a     = product("a.md", title: "A", updated: Time.at(300))
    prim  = product("prim.md", title: "Primary", group: "Kit", primary: true, updated: Time.at(100))
    fresh = product("fresh.md", title: "Fresh", group: "Kit", updated: Time.at(500))
    b     = product("b.md", title: "B", updated: Time.at(200))

    rows = ProductGroup.rows_for([ a, prim, fresh, b ])

    assert rows.first.is_a?(ProductGroup), "group floated to top on its freshest member (500)"
    assert_equal [ prim, fresh ], rows.first.ordered_members, "primary first, then the rest"
    assert_equal [ a, b ], rows[1..], "standalones follow in recency order"
  end

  test "warns when a group has no primary" do
    g1 = product("g1.md", title: "G1", group: "Set")
    g2 = product("g2.md", title: "G2", group: "Set")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_equal 1, group.warnings.size
    assert_match(/no primary/i, group.warnings.first)
    assert_nil group.primary
  end

  test "warns when a group has more than one primary" do
    g1 = product("g1.md", title: "One", group: "Set", primary: true)
    g2 = product("g2.md", title: "Two", group: "Set", primary: true)

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_equal 1, group.warnings.size
    assert_match(/more than one primary/i, group.warnings.first)
    assert_nil group.primary, "ambiguous primary resolves to nil"
  end

  test "a well-formed group with exactly one primary has no warnings" do
    g1 = product("g1.md", title: "Lead", group: "Set", primary: true)
    g2 = product("g2.md", title: "Other", group: "Set")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_empty group.warnings
    assert_equal g1, group.primary
  end

  test "ProductGroup.for resolves a member's group and ignores ungrouped/lone products" do
    g1   = product("g1.md", title: "G1", group: "Boots")
    g2   = product("g2.md", title: "G2", group: "Boots")
    solo = product("solo.md", title: "Solo", group: "OnlyMe")
    none = product("none.md", title: "None")

    assert_equal 2, ProductGroup.for(g1).members.size
    assert_nil ProductGroup.for(solo), "single-member group is not a group"
    assert_nil ProductGroup.for(none), "ungrouped product has no group"
  end
end
