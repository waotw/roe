module LinksHelper
  EDIT_PATHS = { "Post" => :edit_admin_post_path, "Page" => :edit_admin_page_path, "Product" => :edit_admin_product_path }.freeze

  # Where a problem's item name goes: its editor, landing on the reference
  # (`highlight`), on its line or in its metadata field. A link problem
  # also opens the editor's link list there (`link=1`). A doc has no editor
  # in the admin, so it goes to the doc's page. nil when the item has gone
  # since the check.
  def link_problem_path(problem, records)
    return layout_problem_path(problem) if problem["item_type"] == "Layout"

    record = records[[ problem["item_type"], problem["item_id"] ]]
    return nil unless record
    return record.public_url if record.is_a?(Documentation)

    helper = EDIT_PATHS[problem["item_type"]]
    return nil unless helper

    params = { highlight: problem["target"].presence }
    params[:line] = problem["line"] if problem["line"]
    params[:field] = problem["field"] if problem["field"]
    params[:link] = 1 if problem["type"] != "missing_media" && problem["line"]
    public_send(helper, record, params.compact)
  end

  # The layout editor (a plain textarea) selects the reference on that line.
  def layout_problem_path(problem)
    return nil unless LayoutFiles::KEYS.include?(problem["item_id"])

    "/admin/layout/#{problem['item_id']}/edit?" + { highlight: problem["target"], line: problem["line"] }.compact.to_query
  end

  # Every item the problems name, loaded once: { [type, id] => record }.
  def link_problem_records(problems)
    problems.group_by { |p| p["item_type"] }.each_with_object({}) do |(type, list), found|
      model = { "Post" => Post, "Page" => Page, "Product" => Product, "Documentation" => Documentation }[type]
      next unless model

      model.where(id: list.map { |p| p["item_id"] }).each { |record| found[[ type, record.id ]] = record }
    end
  end

  # "line 12" or "audio:".
  def link_problem_where(problem)
    problem["field"] ? "#{problem['field']}:" : "line #{problem['line']}"
  end

  # 10:12 today, Nov 20, 10:12 before that. In the computer's own time zone,
  # like a clock on the wall: the app's zone is UTC.
  def link_check_time(result)
    at = Time.iso8601(result["checked_at"]).localtime
    at.to_date == Time.now.to_date ? at.strftime("%H:%M") : at.strftime("%b %-d, %H:%M")
  rescue ArgumentError, TypeError
    "—"
  end
end
