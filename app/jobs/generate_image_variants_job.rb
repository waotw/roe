# frozen_string_literal: true

class GenerateImageVariantsJob < ApplicationJob
  queue_as :default

  def perform(file_path, medium_id = nil)
    # Normalize path
    normalized_path = normalize_path(file_path)

    return unless File.exist?(normalized_path)
    return unless image_file?(normalized_path)

    # Generate variants (no DB updates needed)
    ImageVariantGenerator.generate_variants(normalized_path, medium_id: nil)
  end

  private

  def normalize_path(path)
    if path.start_with?("/")
      Rails.root.join("site", path.sub(%r{^/}, "")).to_s
    elsif path.start_with?(Rails.root.to_s)
      path
    else
      Rails.root.join("site", path).to_s
    end
  end

  def image_file?(path)
    %w[.jpg .jpeg .png .gif .webp].include?(File.extname(path).downcase)
  end
end
