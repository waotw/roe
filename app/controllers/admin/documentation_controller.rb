class Admin::DocumentationController < Admin::BaseController
  def index
    @docs = Post.documentation.order(Arel.sql("
      CASE
        WHEN file_path LIKE '%/%'
        THEN CAST(SUBSTR(file_path, INSTR(file_path, '/') + 1) AS TEXT)
        ELSE file_path
      END
    "))
  end

  def new
    @doc = Post.new
    @metadata = "---\ntitle: \norder: \n---"
    @content = ""
  end

  def create
    file_name = params[:file_name].parameterize + ".md"
    file_path = File.join(RoeSitePaths::SITE_PATH, "docs", file_name)

    # Build full content
    full_content = params[:metadata] + "\n---\n\n" + params[:content]

    File.write(file_path, full_content)

    # Sync to database
    @doc = Post.create_or_update_from_file(file_path)

    if @doc
      redirect_to admin_documentation_index_path, notice: "Documentation created successfully."
    else
      redirect_to new_admin_documentation_path, alert: "Failed to create documentation."
    end
  end

  def edit
    @doc = Post.find(params[:id])
    raw_content = File.read(@doc.file_path)

    parsed = FrontMatterParser::Parser.new(:md).call(raw_content)

    @metadata = parsed.front_matter.to_yaml.gsub(/^---\n/, "")
    @content = parsed.content
  end

  def update
    @doc = Post.find(params[:id])

    # Build full content
    full_content = params[:metadata] + "\n---\n\n" + params[:content]

    File.write(@doc.file_path, full_content)

    # Re-sync from file
    Post.create_or_update_from_file(@doc.file_path)

    redirect_to admin_documentation_index_path, notice: "Documentation updated successfully."
  end

  def destroy
    @doc = Post.find(params[:id])
    File.delete(@doc.file_path) if File.exist?(@doc.file_path)
    @doc.destroy

    redirect_to admin_documentation_index_path, notice: "Documentation deleted successfully."
  end
end
