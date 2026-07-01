require "test_helper"

# ProductGroup is a derived value object (no table): it buckets products by
# their `group:` front-matter, keeps groups together, floats each group to its
# most-recently-edited member, puts the primary on top, and surfaces the
# no/duplicate-primary setup warnings.
class ProductGroupTest < ActiveSupport::TestCase
  def product(file, title:, group: nil, primary: false, variant: nil, updated: Time.current, status: "published")
    meta = { "title" => title, "status" => status }
    meta["group"] = group if group
    meta["primary"] = true if primary
    meta["variant"] = variant if variant
    p = Product.create!(file_path: file, metadata: meta)
    p.update_column(:updated_at, updated) # control ordering deterministically
    p
  end

  test "ungrouped products are standalone rows, alphabetical by title" do
    a = product("a.md", title: "Cherry", updated: Time.at(300))
    b = product("b.md", title: "Apple", updated: Time.at(500))
    c = product("c.md", title: "Banana", updated: Time.at(100))

    rows = ProductGroup.rows_for([ a, b, c ])

    assert_equal [ b, c, a ], rows, "Apple, Banana, Cherry — regardless of edit time"
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

  test "groups come first (alpha by name), then standalones (alpha by title), primary on top" do
    zebra_a = product("za.md", title: "Alpha", group: "Zebra", primary: true, variant: "x")
    zebra_b = product("zb.md", title: "Beta", group: "Zebra", variant: "y")
    apple_a = product("aa.md", title: "One", group: "Apple", primary: true, variant: "x")
    apple_b = product("ab.md", title: "Two", group: "Apple", variant: "y")
    solo_z  = product("solo-z.md", title: "Zucchini")
    solo_a  = product("solo-a.md", title: "Artichoke")

    rows = ProductGroup.rows_for([ zebra_a, zebra_b, apple_a, apple_b, solo_z, solo_a ])

    assert_equal [ ProductGroup, ProductGroup, Product, Product ], rows.map(&:class)
    assert_equal %w[Apple Zebra], rows[0..1].map(&:name), "groups first, alpha by name"
    assert_equal [ solo_a, solo_z ], rows[2..], "standalones after, alpha by title"
    assert_equal [ apple_a, apple_b ], rows.first.ordered_members, "primary on top within a group"
  end

  test "warns when a group has no primary" do
    g1 = product("g1.md", title: "G1", group: "Set", variant: "A")
    g2 = product("g2.md", title: "G2", group: "Set", variant: "B")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_equal 1, group.warnings.size
    assert_match(/no primary/i, group.warnings.first)
    assert_nil group.primary
  end

  test "warns when a group has more than one primary" do
    g1 = product("g1.md", title: "One", group: "Set", primary: true, variant: "A")
    g2 = product("g2.md", title: "Two", group: "Set", primary: true, variant: "B")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_equal 1, group.warnings.size
    assert_match(/more than one primary/i, group.warnings.first)
    assert_nil group.primary, "ambiguous primary resolves to nil"
  end

  test "a well-formed group with exactly one primary has no warnings" do
    g1 = product("g1.md", title: "Lead", group: "Set", primary: true, variant: "A")
    g2 = product("g2.md", title: "Other", group: "Set", variant: "B")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert_empty group.warnings
    assert_equal g1, group.primary
  end

  test "a missing variant is a group-level warning only when every member lacks one" do
    g1 = product("g1.md", title: "Book", group: "Set", primary: true)
    g2 = product("g2.md", title: "Book", group: "Set")

    group = ProductGroup.new("Set", [ g1, g2 ])
    assert(group.warnings.any? { |w| w.match?(/variant/i) }, "group-level variant warning")
    assert_empty group.row_warnings(g2), "no per-row warning when it's group-wide"
  end

  test "a missing variant is a per-row warning when only some members lack one" do
    g1 = product("g1.md", title: "Book", group: "Set", primary: true, variant: "Hardback")
    g2 = product("g2.md", title: "Book", group: "Set") # no variant

    group = ProductGroup.new("Set", [ g1, g2 ])
    refute(group.warnings.any? { |w| w.match?(/variant/i) }, "not group-wide when only some lack it")
    assert(group.row_warnings(g2).any? { |w| w.match?(/variant/i) })
    assert_empty group.row_warnings(g1)
  end

  test "the two-primaries warning distinguishes products by variant" do
    g1 = product("g1.md", title: "Book", group: "Set", primary: true, variant: "Hardback")
    g2 = product("g2.md", title: "Book", group: "Set", primary: true, variant: "Paperback")

    msg = ProductGroup.new("Set", [ g1, g2 ]).warnings.find { |w| w.match?(/more than one primary/i) }
    assert msg
    assert_includes msg, "Hardback"
    assert_includes msg, "Paperback"
  end

  test "registry_names collects group names from products, deduped case-insensitively and sorted" do
    product("p1.md", title: "A", group: "Zebra")
    product("p2.md", title: "B", group: "apple")
    product("p3.md", title: "C", group: "Apple") # same group, different case
    product("p4.md", title: "D")                  # no group
    product("p5.md", title: "E", group: "  ")     # blank group

    assert_equal %w[apple zebra], ProductGroup.registry_names.map(&:downcase)
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
