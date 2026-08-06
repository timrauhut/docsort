class DocumentsController < ApplicationController
  before_action :set_document, only: %i[show edit update destroy download reclassify assign create_issuer_category]

  def index
    @categories = Category.ordered
    @documents = filtered_documents.limit(200)
    scope = current_user.documents
    @stats = {
      total: scope.count,
      pending: scope.pending.count,
      classified: scope.classified.count,
      failed: scope.failed.count
    }
  end

  def autocomplete
    @documents = filtered_documents.limit(8)
    render partial: "documents/autocomplete", locals: { documents: @documents }
  end

  def show
  end

  def new
    @document = current_user.documents.new
    @categories = Category.ordered
  end

  def create
    files = Array(params.dig(:document, :files)).reject(&:blank?)
    if files.empty? && params.dig(:document, :file).present?
      files = [ params[:document][:file] ]
    end

    if files.empty?
      redirect_to new_document_path, alert: "Choose at least one file to upload."
      return
    end

    oversized = files.find { |uploaded| uploaded.size.to_i > Rails.application.config.x.max_upload_bytes }
    if oversized
      redirect_to new_document_path, alert: "#{oversized.original_filename} exceeds the upload limit."
      return
    end

    created = files.map do |uploaded|
      DocumentIngestor.new(
        io: uploaded.tempfile,
        filename: uploaded.original_filename,
        source: "web",
        content_type: uploaded.content_type,
        user: current_user
      ).call
    end

    redirect_to documents_path, notice: "Uploaded #{created.size} document(s). Classification started."
  rescue DocumentIngestor::InvalidUpload => e
    redirect_to new_document_path, alert: e.message
  end

  def edit
    @categories = Category.ordered
  end

  def update
    if @document.update(document_params)
      if @document.saved_change_to_category_id?
        if @document.category
          DocumentOrganizer.new(@document).call
        else
          SortedCopy.remove(@document)
          @document.update_column(:relative_path, nil)
        end
      end
      redirect_to @document, notice: "Document updated."
    else
      @categories = Category.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path, notice: "Document deleted."
  end

  def download
    if @document.file.attached?
      redirect_to rails_blob_path(@document.file, disposition: "attachment")
    else
      redirect_to @document, alert: "No file attached."
    end
  end

  def reclassify
    @document.reclassify!
    redirect_to @document, notice: "Reclassification queued."
  end

  def assign
    category = Category.find(params[:category_id])
    @document.update!(
      category: category,
      status: "classified",
      classifier_used: "manual",
      classified_at: Time.current,
      confidence: 1.0
    )
    DocumentOrganizer.new(@document).call
    redirect_to @document, notice: "Moved to #{category.name}."
  end

  # Create (or reuse) a category from the detected letterhead / brand issuer.
  def create_issuer_category
    if @document.issuer.blank?
      redirect_to @document, alert: "No issuer detected on this document."
      return
    end

    category = IssuerCategoryResolver.new(
      @document.issuer,
      confidence: [ @document.issuer_confidence.to_f, 0.9 ].max,
      auto_create: true
    ).call

    if category
      @document.update!(
        category: category,
        status: "classified",
        classifier_used: "issuer-category",
        classified_at: Time.current,
        confidence: [ @document.confidence.to_f, 0.85 ].max
      )
      DocumentOrganizer.new(@document).call
      redirect_to @document, notice: "Created category “#{category.name}” and filed the document."
    else
      redirect_to @document, alert: "Could not create a category for this issuer."
    end
  end

  private

  def set_document
    @document = current_user.documents.find(params[:id])
  end

  def filtered_documents
    scope = current_user.documents.includes(:category).recent
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.search(params[:q]) if params[:q].present?
    scope
  end

  def document_params
    params.require(:document).permit(:title, :summary, :tags, :category_id, :status)
  end
end
